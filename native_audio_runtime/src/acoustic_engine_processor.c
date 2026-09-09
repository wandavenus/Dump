// Acoustic Engine implementation. This is deliberately not a bass-boost or
// gain stage: it removes unreproducible sub-bass, adds a very small
// bandwidth-limited harmonic cue, adds presence, and dynamically eases the
// harsh band as programme level rises. All history is stream-local.
#include "acoustic_engine_processor.h"

#include <math.h>
#include <stdatomic.h>
#include <string.h>

#include "audio_buffer_internal.h"
#include "biquad_filter.h"
#include "dsp_pipeline.h"
#include "dsp_processor.h"
#include "dsp_stream.h"
#include "native_audio_runtime_internal.h"

#define AE_CHANNELS NAR_BIQUAD_MAX_CHANNELS

typedef struct {
  float intensity, pre_gain, harmonic_mix, presence_mix, harsh_mix;
  NarBiquadCoeffs sub_hp, bass_lp, harmonic_hp, presence, harsh_bp;
} AeParams;

typedef struct {
  AeParams pending;
  AeParams active[NAR_DSP_MAX_STREAMS];
  _Atomic int32_t dirty[NAR_DSP_MAX_STREAMS];
  _Atomic int32_t bypass;
  NarBiquadState sub_hp[NAR_DSP_MAX_STREAMS];
  NarBiquadState bass_lp[NAR_DSP_MAX_STREAMS];
  NarBiquadState harmonic_hp[NAR_DSP_MAX_STREAMS];
  NarBiquadState presence[NAR_DSP_MAX_STREAMS];
  NarBiquadState harsh_bp[NAR_DSP_MAX_STREAMS];
  float envelope[NAR_DSP_MAX_STREAMS];
} AeState;

static AeState _ae;
static _Atomic int32_t _sample_rate = 48000;

static float _clampf(float x, float lo, float hi) {
  return x < lo ? lo : (x > hi ? hi : x);
}

static AeParams _build(float intensity, float sample_rate) {
  AeParams p;
  const float i = _clampf(isfinite(intensity) ? intensity : 0.0f, 0.0f, 1.0f);
  const float sr = sample_rate > 1000.0f ? sample_rate : 48000.0f;
  p.intensity = i;
  // Small pre-compensation reserves headroom for the bounded additions below.
  p.pre_gain = 1.0f - 0.10f * i;
  p.harmonic_mix = 0.055f * i;
  p.presence_mix = 0.105f * i;
  p.harsh_mix = 0.18f * i;
  nar_biquad_compute(NAR_BIQUAD_HIGH_PASS, 48.0f, 0.7071f, 0.0f, sr, &p.sub_hp);
  nar_biquad_compute(NAR_BIQUAD_LOW_PASS, 185.0f, 0.7071f, 0.0f, sr, &p.bass_lp);
  // Removes the DC made by x*abs(x), while retaining speaker-reproducible
  // second-harmonic content from the bass band.
  nar_biquad_compute(NAR_BIQUAD_HIGH_PASS, 105.0f, 0.7071f, 0.0f, sr, &p.harmonic_hp);
  nar_biquad_compute(NAR_BIQUAD_PEAK, 2450.0f, 0.85f, 1.0f, sr, &p.presence);
  nar_biquad_compute(NAR_BIQUAD_BAND_PASS, 4800.0f, 0.90f, 0.0f, sr, &p.harsh_bp);
  return p;
}

static void _clear_stream(int s) {
  memset(&_ae.sub_hp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.bass_lp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.harmonic_hp[s], 0, sizeof(NarBiquadState));
  memset(&_ae.presence[s], 0, sizeof(NarBiquadState));
  memset(&_ae.harsh_bp[s], 0, sizeof(NarBiquadState));
  _ae.envelope[s] = 0.0f;
}

static int32_t _init(void* self) {
  (void)self;
  memset(&_ae, 0, sizeof(_ae));
  _ae.pending = _build(0.50f, 48000.0f);
  for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) {
    _ae.active[s] = _ae.pending;
    atomic_store(&_ae.dirty[s], 0);
  }
  atomic_store(&_ae.bypass, 1); // off by default: transparent until user enables it
  return NATIVE_RUNTIME_OK;
}

static int32_t _process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  if (buffer == NULL || buffer->data == NULL || buffer->channel_count <= 0 ||
      buffer->channel_count > AE_CHANNELS) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  if (atomic_load_explicit(&_ae.bypass, memory_order_acquire)) return NATIVE_RUNTIME_OK;
  const int s = nar_dsp_clamp_stream(stream_slot);
  if (atomic_exchange_explicit(&_ae.dirty[s], 0, memory_order_acq_rel)) {
    _ae.active[s] = _ae.pending;
    _clear_stream(s);
  }
  const AeParams* p = &_ae.active[s];
  const int channels = buffer->channel_count;
  for (int32_t f = 0; f < buffer->frame_count; ++f) {
    float peak = 0.0f;
    for (int c = 0; c < channels; ++c) {
      const float x = buffer->data[f * channels + c];
      if (!isfinite(x)) { buffer->data[f * channels + c] = 0.0f; return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT; }
      const float a = fabsf(x); if (a > peak) peak = a;
    }
    // Stereo-linked detector: no left/right image movement. Fast attack,
    // relaxed release; protection appears only when programme level is high.
    const float coeff = peak > _ae.envelope[s] ? 0.020f : 0.0012f;
    _ae.envelope[s] += coeff * (peak - _ae.envelope[s]);
    const float protect = _clampf((_ae.envelope[s] - 0.38f) / 0.52f, 0.0f, 1.0f);
    const float adaptive = 1.0f - 0.70f * protect;
    for (int c = 0; c < channels; ++c) {
      const int n = f * channels + c;
      const float x = buffer->data[n];
      const float tight = nar_biquad_process_sample(&p->sub_hp, &_ae.sub_hp[s].s1[c], &_ae.sub_hp[s].s2[c], x);
      const float bass = nar_biquad_process_sample(&p->bass_lp, &_ae.bass_lp[s].s1[c], &_ae.bass_lp[s].s2[c], tight);
      const float even_harmonic = bass * fabsf(bass);
      const float harmonic = nar_biquad_process_sample(&p->harmonic_hp, &_ae.harmonic_hp[s].s1[c], &_ae.harmonic_hp[s].s2[c], even_harmonic);
      const float presence = nar_biquad_process_sample(&p->presence, &_ae.presence[s].s1[c], &_ae.presence[s].s2[c], tight) - tight;
      const float harsh = nar_biquad_process_sample(&p->harsh_bp, &_ae.harsh_bp[s].s1[c], &_ae.harsh_bp[s].s2[c], tight);
      float y = p->pre_gain * tight + adaptive * (p->harmonic_mix * harmonic + p->presence_mix * presence) - protect * p->harsh_mix * harsh;
      // This is a finite guard, not a second limiter; limiter/clipper remain
      // the final safety stages. It only bounds hostile non-audio input.
      if (!isfinite(y)) y = 0.0f;
      buffer->data[n] = _clampf(y, -4.0f, 4.0f);
    }
  }
  return NATIVE_RUNTIME_OK;
}

static void _reset(void* self) { (void)self; for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) _clear_stream(s); }
static void _dispose(void* self) { (void)self; _reset(NULL); }
static int32_t _latency(void* self) { (void)self; return 0; }
static const NarDspProcessorVTable _vtable = {_init, _process, _reset, _dispose, _latency};

FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_processor_register_internal(void) {
  const NarDspProcessorDescriptor d = {"dsp.acoustic_engine", &_ae, &_vtable};
  return nar_dsp_pipeline_register_internal(&d);
}
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity) {
  _ae.pending = _build(intensity, (float)atomic_load_explicit(&_sample_rate, memory_order_acquire));
  for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) atomic_store_explicit(&_ae.dirty[s], 1, memory_order_release);
}
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void) { return _ae.pending.intensity; }
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_ae.bypass, bypass ? 1 : 0, memory_order_release);
  _reset(NULL);
}
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void) { return atomic_load_explicit(&_ae.bypass, memory_order_acquire); }
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_sample_rate(int32_t sample_rate) {
  const int32_t rate = sample_rate > 1000 ? sample_rate : 48000;
  atomic_store_explicit(&_sample_rate, rate, memory_order_release);
  _ae.pending = _build(_ae.pending.intensity, (float)rate);
  for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) atomic_store_explicit(&_ae.dirty[s], 1, memory_order_release);
}
FFI_PLUGIN_EXPORT void nar_acoustic_engine_reset(void) { _reset(NULL); }
