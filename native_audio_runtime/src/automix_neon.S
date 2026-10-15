// ARM64 frame windowing + RMS accumulation for the AutoMix STFT.
// The FFT itself stays portable C; this hot per-frame PCM loop uses NEON SIMD.

#ifdef __aarch64__
    .text
    .align  4
    .global nar_automix_window_rms_neon
    .type   nar_automix_window_rms_neon, %function

// float nar_automix_window_rms_neon(
//     const float* pcm, const float* hann, float* fft_real, int32_t count)
//     x0             x1                x2             w3
//
// count is always FFT_SIZE (2048), therefore a multiple of four. v0 accumulates
// unwindowed sample power while v3 writes the Hann-windowed FFT input.
nar_automix_window_rms_neon:
    movi    v0.4s, #0
    cbz     w3, .Lautomix_neon_reduce
.Lautomix_neon_loop:
    ldr     q1, [x0], #16
    ldr     q2, [x1], #16
    fmul    v3.4s, v1.4s, v2.4s
    str     q3, [x2], #16
    fmla    v0.4s, v1.4s, v1.4s
    subs    w3, w3, #4
    b.ne    .Lautomix_neon_loop
.Lautomix_neon_reduce:
    faddp   v0.4s, v0.4s, v0.4s
    faddp   s0, v0.2s
    ret
    .size nar_automix_window_rms_neon, . - nar_automix_window_rms_neon
#endif
