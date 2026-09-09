// Acoustic Engine — lightweight, zero-latency native speaker enhancement.
#include "acoustic_engine_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
#include "native_audio_runtime_internal.h"

// Keep this processor deliberately conservative: it shapes reproducible bass,
// adds a bandwidth-limited harmonic cue, and dynamically relaxes harsh HF.
#define AE_MAX_CHANNELS NAR_BIQUAD_MAX_CHANNELS

typedef struct {
  NarBiquadCoeffs sub_high_pass;
  NarBiquadCoeffs bass_low_pass;
  NarBiquadCoeffs presence;
  NarBiquadCoeffs harsh_high_pass;
  float intensity;
} AeParams;

typedef struct {
  AeParams pending;
  AeParams active[NAR_DSP_MAX_STREAMS];
  _Atomic int32_t dirty[NAR_DSP_MAX_STREAMS];
  _Atomic uint32_t intensity_bits;
  _Atomic int32_t bypass;
  int32_t sample_rate[NAR_DSP_MAX_STREAMS];
  NarBiquadState sub_hp[NAR_DSP_MAX_STREAMS];
  NarBiquadState bass_lp[NAR_DSP_MAX_STREAMS];
  NarBiquadState harmonic_lp[NAR_DSP_MAX_STREAMS];
  NarBiquadState presence[NAR_DSP_MAX_STREAMS];
  NarBiquadState harsh_hp[NAR_DSP_MAX_STREAMS];
  float level[NAR_DSP_MAX_STREAMS];
} AeState;

static AeState _ae;

static uint32_t _float_to_bits(float value) {
  uint32_t bits;
  memcpy(&bits, &value, sizeof(bits));
  return bits;
}
static float _bits_to_float(uint32_t bits) {
  float value;
  memcpy(&value, &bits, sizeof(value));
  return value;
}
static float _clampf(float value, float lo, float hi) {
  return value < lo ? lo : (value > hi ? hi : value);
}

static void _reset_stream(int32_t s) {
  memset(&_ae.sub_hp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.bass_lp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.harmonic_lp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.presence[s], 0, sizeof(NarBiquadState));
  memset(&_ae.harsh_hp[s], 0, sizeof(NarBiquadState));
  _ae.level[s] = 0.0f;
}

// Called only from init/control updates, plus the rare buffer rate transition.
// The latter is required because the actual NarAudioBuffer rate is authoritative.
static void _build_params(AeParams* out, float intensity, int32_t sample_rate) {
  if (sample_rate <= 0) sample_rate = 48000;
  const float i = _clampf(intensity, 0.0f, 100.0f) * 0.01f;
  out->intensity = i;
  // At most 1.5 dB of low-shelf-like bass restoration; the 55 Hz high-pass
  // removes demanding sub-bass rather than attempting to reproduce it.
  (void)nar_biquad_compute(NAR_BIQUAD_HIGH_PASS, 55.0f, 0.707f, 0.0f,
                           (float)sample_rate, &out->sub_high_pass);
  (void)nar_biquad_compute(NAR_BIQUAD_LOW_PASS, 190.0f, 0.707f, 0.0f,
                           (float)sample_rate, &out->bass_low_pass);
  (void)nar_biquad_compute(NAR_BIQUAD_PEAK, 2200.0f, 0.85f, 1.35f * i,
                           (float)sample_rate, &out->presence);
  (void)nar_biquad_compute(NAR_BIQUAD_HIGH_PASS, 4200.0f, 0.707f, 0.0f,
                           (float)sample_rate, &out->harsh_high_pass);
}

static void _ensure_sample_rate(int32_t s, int32_t sample_rate) {
  if (sample_rate <= 0) sample_rate = 48000;
  if (_ae.sample_rate[s] == sample_rate) return;
  _build_params(&_ae.active[s], _ae.active[s].intensity * 100.0f, sample_rate);
  _ae.sample_rate[s] = sample_rate;
  _reset_stream(s);
}

static int32_t _ae_init(void* self) {
  (void)self;
  AeParams defaults;
  _build_params(&defaults, 50.0f, 48000);
  _ae.pending = defaults;
  atomic_store(&_ae.intensity_bits, _float_to_bits(50.0f));
  atomic_store(&_ae.bypass, 1);  // explicit opt-in; transparent at startup.
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; ++s) {
    _ae.active[s] = defaults;
    _ae.sample_rate[s] = 0;
    atomic_store(&_ae.dirty[s], 0);
    _reset_stream(s);
  }
  return NATIVE_RUNTIME_OK;
}

static int32_t _ae_process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  const int32_t s = nar_dsp_clamp_stream(stream_slot);
  if (atomic_load_explicit(&_ae.bypass, memory_order_relaxed)) return NATIVE_RUNTIME_OK;
  if (atomic_load_explicit(&_ae.dirty[s], memory_order_acquire)) {
    _ae.active[s] = _ae.pending;
    _ae.sample_rate[s] = 0;
    atomic_store_explicit(&_ae.dirty[s], 0, memory_order_relaxed);
  }
  float* data = nar_audio_buffer_data(buffer);
  if (data == NULL) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  const int32_t frames = nar_audio_buffer_frame_count(buffer);
  const int32_t channels = nar_audio_buffer_channel_count(buffer);
  if (frames <= 0 || channels <= 0) return NATIVE_RUNTIME_OK;
  if (channels > AE_MAX_CHANNELS) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  _ensure_sample_rate(s, nar_audio_buffer_sample_rate(buffer));
  const AeParams* p = &_ae.active[s];
  if (p->intensity <= 0.0f) return NATIVE_RUNTIME_OK;
  float level = _ae.level[s];
  const float envelope_release = 0.9992f;
  for (int32_t f = 0; f < frames; ++f) {
    const int32_t base = f * channels;
    float peak = 0.0f;
    for (int32_t c = 0; c < channels; ++c) {
      float x = data[base + c];
      if (!isfinite(x)) x = data[base + c] = 0.0f;
      const float a = fabsf(x);
      if (a > peak) peak = a;
    }
    level = peak > level ? peak : envelope_release * level + (1.0f - envelope_release) * peak;
    // Fade enrichment as the signal approaches full scale, leaving final
    // protection to the existing compressor/limiter/soft-clipper stages.
    const float protection = _clampf((level - 0.45f) * 1.6f, 0.0f, 1.0f);
    const float enhancement = p->intensity * (1.0f - 0.72f * protection);
    const float harmonic_mix = 0.055f * enhancement;
    const float harsh_cut = 0.22f * p->intensity * protection;
    for (int32_t c = 0; c < channels; ++c) {
      const float x = data[base + c];
      const float tight = nar_biquad_process_sample(&p->sub_high_pass,
          &_ae.sub_hp[s].s1[c], &_ae.sub_hp[s].s2[c], x);
      const float bass = nar_biquad_process_sample(&p->bass_low_pass,
          &_ae.bass_lp[s].s1[c], &_ae.bass_lp[s].s2[c], tight);
      // x*abs(x) is a soft, bounded harmonic generator. Removing its low
      // component avoids DC/sub-bass build-up and keeps it speaker-friendly.
      const float harmonic_source = bass * fabsf(bass);
      const float harmonic_low = nar_biquad_process_sample(&p->bass_low_pass,
          &_ae.harmonic_lp[s].s1[c], &_ae.harmonic_lp[s].s2[c], harmonic_source);
      const float presence = nar_biquad_process_sample(&p->presence,
          &_ae.presence[s].s1[c], &_ae.presence[s].s2[c], tight);
      const float harsh = nar_biquad_process_sample(&p->harsh_high_pass,
          &_ae.harsh_hp[s].s1[c], &_ae.harsh_hp[s].s2[c], presence);
      float y = presence + harmonic_mix * (harmonic_source - harmonic_low) - harsh_cut * harsh;
      data[base + c] = isfinite(y) ? y : x;  // fail-open for invalid math.
    }
  }
  _ae.level[s] = isfinite(level) ? level : 0.0f;
  return NATIVE_RUNTIME_OK;
}

static void _ae_reset(void* self) {
  (void)self;
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; ++s) _reset_stream(s);
}
static void _ae_dispose(void* self) { (void)self; _ae_reset(NULL); atomic_store(&_ae.bypass, 1); }
static int32_t _ae_latency(void* self) { (void)self; return 0; }
static const NarDspProcessorVTable kAeVTable = {
  .init = _ae_init, .process = _ae_process, .reset = _ae_reset,
  .dispose = _ae_dispose, .latency_frames = _ae_latency,
};

FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_processor_register_internal(void) {
  const NarDspProcessorDescriptor desc = { .id = "dsp.acoustic_engine", .self = NULL, .vtable = &kAeVTable };
  return nar_dsp_pipeline_register_internal(&desc);
}
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity) {
  intensity = _clampf(isfinite(intensity) ? intensity : 0.0f, 0.0f, 100.0f);
  AeParams p;
  _build_params(&p, intensity, 48000);  // per-stream rate is rebuilt on adoption.
  _ae.pending = p;
  atomic_store(&_ae.intensity_bits, _float_to_bits(intensity));
  for (int32_t s = 0; s < NAR_DSP_MAX_STREAMS; ++s)
    atomic_store_explicit(&_ae.dirty[s], 1, memory_order_release);
}
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void) {
  return _bits_to_float(atomic_load(&_ae.intensity_bits));
}
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass) {
  atomic_store(&_ae.bypass, bypass ? 1 : 0);
  _ae_reset(NULL);  // no stale filter/envelope history crosses a toggle.
}
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void) { return atomic_load(&_ae.bypass); }
