// Acoustic Engine implementation. This is deliberately not a bass-boost or
// gain stage: it removes unreproducible sub-bass, adds a very small
// bandwidth-limited harmonic cue, adds presence, and dynamically eases the
// harsh band as programme level rises. All history is stream-local.
//
// ── Concurrency contract (C11 memory model) ──────────────────────────────────
//
// The control thread (UI / Dart FFI) publishes the user's intensity as ONE
// atomic scalar (`intensity_bits`, IEEE-754 float bits, release store). No
// shared mutable struct is written from the control path: a struct + dirty
// flag cannot be published safely under repeated concurrent writes, because
// the writer may overwrite the struct while the audio thread is copying it
// (torn read — undefined behavior). A single atomic scalar has no such
// window; every store and load is atomic and last-writer-wins is defined.
//
// Each audio thread loads the scalar (acquire) on every process() call and
// compares it against the value it has already applied for its stream. When
// the published intensity differs, or the buffer's sample rate changed, the
// audio thread ALONE rebuilds its per-stream AeParams snapshot and clears
// its own filter history. Coefficients (sin/cos/pow inside
// nar_biquad_compute) are therefore computed only on the audio thread and
// only on an actual change — never per frame, never on the control thread,
// and never while another thread could touch the same struct.
//
// Bypass and reset follow the same shape: the control thread only stores
// atomics (`bypass`, `reset_gen`); every audio thread detects the change
// itself and clears its own histories, so a toggle can never race with an
// in-flight render and no DSP state is touched from the control thread.
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
  // ── Control-plane state: atomics only, no structs cross threads ───────────
  // `intensity_bits` holds the latest requested intensity as IEEE-754 float
  // bits; `bypass` is the on/off switch; `rate_hint` is the fallback sample
  // rate used when a buffer does not carry one; `reset_gen` is bumped to ask
  // every audio thread to clear its own history. All are written only by the
  // control thread and read by the audio threads.
  _Atomic uint32_t intensity_bits;
  _Atomic int32_t bypass;
  _Atomic int32_t rate_hint;
  _Atomic uint32_t reset_gen;

  // ── Audio-thread-only state, per stream. NEVER touched by control code. ──
  AeParams active[NAR_DSP_MAX_STREAMS];
  uint32_t applied_bits[NAR_DSP_MAX_STREAMS];  // intensity bits active[s] built for
  int32_t applied_rate[NAR_DSP_MAX_STREAMS];   // rate active[s] built for
  uint32_t seen_reset_gen[NAR_DSP_MAX_STREAMS];
  int32_t last_bypass[NAR_DSP_MAX_STREAMS];    // bypass seen by previous process()
  NarBiquadState sub_hp[NAR_DSP_MAX_STREAMS];
  NarBiquadState bass_lp[NAR_DSP_MAX_STREAMS];
  NarBiquadState harmonic_hp[NAR_DSP_MAX_STREAMS];
  NarBiquadState presence[NAR_DSP_MAX_STREAMS];
  NarBiquadState harsh_bp[NAR_DSP_MAX_STREAMS];
  float envelope[NAR_DSP_MAX_STREAMS];
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

static float _clampf(float x, float lo, float hi) {
  return x < lo ? lo : (x > hi ? hi : x);
}

// Pure function of its arguments: reads no shared state, so it is safe to run
// on the audio thread (and is never called from the control thread).
static AeParams _build(float intensity, int32_t sample_rate) {
  AeParams p;
  const float i = _clampf(isfinite(intensity) ? intensity : 0.0f, 0.0f, 1.0f);
  const float sr = (float)(sample_rate > 1000 ? sample_rate : 48000);
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
  const uint32_t default_bits = _float_to_bits(0.50f);
  const AeParams defaults = _build(0.50f, 48000);
  for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) {
    _ae.active[s] = defaults;
    _ae.applied_bits[s] = default_bits;
    _ae.applied_rate[s] = 48000;
    _ae.last_bypass[s] = 1;
  }
  atomic_store_explicit(&_ae.intensity_bits, default_bits, memory_order_release);
  atomic_store_explicit(&_ae.bypass, 1, memory_order_release);  // transparent until enabled
  atomic_store_explicit(&_ae.rate_hint, 48000, memory_order_release);
  atomic_store_explicit(&_ae.reset_gen, 0, memory_order_release);
  return NATIVE_RUNTIME_OK;
}

static int32_t _process(void* self, NarAudioBuffer* buffer, int32_t stream_slot) {
  (void)self;
  if (buffer == NULL || buffer->data == NULL || buffer->channel_count <= 0 ||
      buffer->channel_count > AE_CHANNELS) return NATIVE_RUNTIME_ERROR_INVALID_ARGUMENT;
  const int s = nar_dsp_clamp_stream(stream_slot);

  // Observe control-plane changes on the audio thread; clear own state only.
  const int32_t bypass = atomic_load_explicit(&_ae.bypass, memory_order_acquire);
  if (bypass != _ae.last_bypass[s]) {
    _ae.last_bypass[s] = bypass;
    _clear_stream(s);
  }
  const uint32_t gen = atomic_load_explicit(&_ae.reset_gen, memory_order_acquire);
  if (gen != _ae.seen_reset_gen[s]) {
    _ae.seen_reset_gen[s] = gen;
    _clear_stream(s);
  }
  if (bypass) return NATIVE_RUNTIME_OK;

  int32_t rate = buffer->sample_rate;
  if (rate <= 0) rate = atomic_load_explicit(&_ae.rate_hint, memory_order_acquire);
  if (rate <= 1000) rate = 48000;

  // Detect a published intensity change or a rate change; rebuild the
  // per-stream snapshot only then (coefficients live on the audio thread).
  const uint32_t published = atomic_load_explicit(&_ae.intensity_bits, memory_order_acquire);
  if (published != _ae.applied_bits[s] || rate != _ae.applied_rate[s]) {
    _ae.active[s] = _build(_bits_to_float(published), rate);
    _ae.applied_bits[s] = published;
    _ae.applied_rate[s] = rate;
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

// Called by the pipeline (same thread that drives process()): clearing every
// stream directly is safe here.
static void _reset(void* self) {
  (void)self;
  for (int s = 0; s < NAR_DSP_MAX_STREAMS; ++s) _clear_stream(s);
}
static void _dispose(void* self) { (void)self; _reset(NULL); }
static int32_t _latency(void* self) { (void)self; return 0; }
static const NarDspProcessorVTable _vtable = {_init, _process, _reset, _dispose, _latency};

FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_processor_register_internal(void) {
  const NarDspProcessorDescriptor d = {"dsp.acoustic_engine", &_ae, &_vtable};
  return nar_dsp_pipeline_register_internal(&d);
}

// Control thread: publish the latest intensity as ONE atomic scalar (release
// store). No struct is written, so rapid repeated calls while the audio
// thread is rendering are well-defined (atomic, last-writer-wins).
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_intensity(float intensity) {
  const float clamped = _clampf(isfinite(intensity) ? intensity : 0.0f, 0.0f, 1.0f);
  atomic_store_explicit(&_ae.intensity_bits, _float_to_bits(clamped), memory_order_release);
}
FFI_PLUGIN_EXPORT float nar_acoustic_engine_get_intensity(void) {
  return _bits_to_float(atomic_load_explicit(&_ae.intensity_bits, memory_order_acquire));
}
// Control thread: only the bypass scalar is stored here. Per-stream filter
// histories are cleared by each audio thread when it observes the transition
// (see _process), so this never races with an in-flight render.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_bypass(int32_t bypass) {
  atomic_store_explicit(&_ae.bypass, bypass ? 1 : 0, memory_order_release);
}
FFI_PLUGIN_EXPORT int32_t nar_acoustic_engine_get_bypass(void) {
  return atomic_load_explicit(&_ae.bypass, memory_order_acquire);
}
// The actual buffer sample rate is authoritative (see _process); this stores
// only the fallback hint used for buffers that carry no rate. Kept for API
// compatibility with the Dart control facade.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_set_sample_rate(int32_t sample_rate) {
  const int32_t rate = sample_rate > 1000 ? sample_rate : 48000;
  atomic_store_explicit(&_ae.rate_hint, rate, memory_order_release);
}
// Control thread: bump the generation so every audio thread clears its own
// history on its next process() call.
FFI_PLUGIN_EXPORT void nar_acoustic_engine_reset(void) {
  (void)atomic_fetch_add_explicit(&_ae.reset_gen, 1u, memory_order_acq_rel);
}
