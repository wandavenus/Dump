// Stereo AutoMix tone processing: two independent channel states in NEON lanes.
// The mono and multichannel paths remain in automix_tone_processor.c.

#ifdef __aarch64__
    .text
    .align  4
    .global nar_automix_tone_process_stereo_neon
    .type   nar_automix_tone_process_stereo_neon, %function

// void nar_automix_tone_process_stereo_neon(
//     float* pcm, int32_t frames, NarAutomixToneState* state,
//     float target_bass, float target_mid, float target_high, float target_fade)
//     x0       w1             x2                 s0            s1           s2
//     s3
//
// NarAutomixToneState offsets are compile-time checked in the C translation
// unit. v8-v15 are callee-saved by AAPCS64, so preserve their low 64 bits.
nar_automix_tone_process_stereo_neon:
    stp     d8, d9, [sp, #-64]!
    stp     d10, d11, [sp, #16]
    stp     d12, d13, [sp, #32]
    stp     d14, d15, [sp, #48]

    fmov    s12, s0
    fmov    s13, s1
    fmov    s22, s2
    fmov    s17, s3
    ldr     d0, [x2]
    ldr     d1, [x2, #32]
    ldr     s10, [x2, #64]
    dup     v4.2s, v10.s[0]
    ldr     s11, [x2, #68]
    dup     v5.2s, v11.s[0]
    ldr     s16, [x2, #72]
    ldr     s14, [x2, #76]
    ldr     s15, [x2, #80]
    ldr     s18, [x2, #92]
    ldr     s21, [x2, #100]
    scvtf   s19, w1
    fsub    s20, s17, s18
    fdiv    s20, s20, s19
    ldr     q31, .Lautomix_tone_max_finite
    cbz     w1, .Lautomix_tone_store

.Lautomix_tone_loop:
    // Smooth all three isolator gains at a 20 ms time constant.
    fsub    s9, s12, s14
    fmul    s9, s9, s16
    fadd    s14, s14, s9
    fsub    s9, s13, s21
    fmul    s9, s9, s16
    fadd    s21, s21, s9
    fsub    s9, s22, s15
    fmul    s9, s9, s16
    fadd    s15, s15, s9
    fadd    s18, s18, s20

    // Load and sanitize one interleaved L/R frame before updating IIR history.
    ld1     {v2.2s}, [x0]
    fabs    v3.2s, v2.2s
    fcmle   v6.2s, v3.2s, v31.2s
    movi    v3.2s, #0
    bsl     v6.8b, v2.8b, v3.8b

    // Split into complementary low (<150 Hz), mid (150 Hz–1.2 kHz),
    // and high (>1.2 kHz) bands. The bands sum back to the input signal.
    fsub    v3.2s, v6.2s, v0.2s
    fmla    v0.2s, v3.2s, v4.2s

    fsub    v7.2s, v6.2s, v1.2s
    fmla    v1.2s, v7.2s, v5.2s

    // output = low*bassGain + mid*midGain + high*highGain
    fsub    v7.2s, v6.2s, v1.2s
    fsub    v3.2s, v1.2s, v0.2s
    dup     v9.2s, v21.s[0]
    fmul    v3.2s, v3.2s, v9.2s
    dup     v9.2s, v14.s[0]
    fmla    v3.2s, v0.2s, v9.2s
    dup     v9.2s, v15.s[0]
    fmla    v3.2s, v7.2s, v9.2s
    // Clamp the post-EQ signal BEFORE the crossfade envelope. Otherwise
    // an over-range sample can saturate after fading and defeat the combined
    // L1 gain budget when Android mixes the two AudioTracks.
    ldr     q29, .Lautomix_tone_one
    ldr     q30, .Lautomix_tone_negative_one
    fmax    v3.2s, v3.2s, v30.2s
    fmin    v3.2s, v3.2s, v29.2s
    dup     v9.2s, v18.s[0]
    fmul    v3.2s, v3.2s, v9.2s
    // Defensive final sample-peak ceiling; this is not true-peak limiting.
    fmax    v3.2s, v3.2s, v30.2s
    fmin    v3.2s, v3.2s, v29.2s
    st1     {v3.2s}, [x0]
    add     x0, x0, #8
    subs    w1, w1, #1
    b.ne    .Lautomix_tone_loop

.Lautomix_tone_store:
    str     d0, [x2]
    str     d1, [x2, #32]
    str     s14, [x2, #76]
    str     s15, [x2, #80]
    str     s18, [x2, #92]
    str     s21, [x2, #100]

    ldp     d14, d15, [sp, #48]
    ldp     d12, d13, [sp, #32]
    ldp     d10, d11, [sp, #16]
    ldp     d8, d9, [sp], #64
    ret

    .align  4
.Lautomix_tone_max_finite:
    .word   0x7f7fffff, 0x7f7fffff, 0, 0
.Lautomix_tone_one:
    .word   0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000
.Lautomix_tone_negative_one:
    .word   0xbf800000, 0xbf800000, 0xbf800000, 0xbf800000

    .size nar_automix_tone_process_stereo_neon, . - nar_automix_tone_process_stereo_neon
#endif
