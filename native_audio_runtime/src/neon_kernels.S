// neon_kernels.S — ARM64 NEON optimized audio processing kernels
//
// Target  : AArch64 (arm64-v8a) with NEON / Advanced SIMD
// Compiler: clang (Android NDK) — assembled via the C preprocessor
// ABI     : AAPCS64
//
// AAPCS64 quick-reference:
//   Integer / pointer args : x0–x7   (w0–w7 for 32-bit values)
//   Scalar float args      : s0–s7   (alias v0.s[0] … v7.s[0])
//   Caller-saved NEON      : v0–v7, v16–v31  (free to clobber)
//   Callee-saved NEON      : d8–d15  (only low 64 bits of v8–v15 are saved;
//                                     use v16–v31 for temporaries instead)
//   Return integer/pointer : x0
//   Return float           : s0
//
// Guard: the whole file is compiled only for AArch64.  For x86_64 (host
// unit-test builds) the CBuilder sees an empty translation unit.

#ifdef __aarch64__

    .text
    .align  4


// =============================================================================
// nar_gain_apply_neon
//
// void nar_gain_apply_neon(float* data, int32_t samples, float gain_linear)
//                           x0            w1               s0
//
// Multiply every sample in data[0..samples-1] by gain_linear in-place.
//
// Algorithm:
//   1. Broadcast scalar gain → v16.4s  = {g, g, g, g}
//   2. Main loop: 16 samples per iteration
//        ldp  q,q,q,q  → 4× fmul v.4s → stp q,q,q,q
//        (Snapdragon 730: dual-issue FMUL, 4 cycles throughput for 16 floats)
//   3. Tail-4 loop: 0–3 remaining 4-sample chunks
//   4. Tail-1 loop: 0–3 remaining individual samples (scalar fmul s,s,s)
//
// The gain is already computed as a finite linear value by the C caller
// (powf path on the control thread, with an isfinite() guard).  Non-finite
// samples in the buffer are intentionally NOT re-checked here — the caller's
// comment notes the NEON auto-vectorizable version also omits isfinite() for
// the same reason, and the soft_clipper at the end of the chain is the
// pipeline-wide safety net.
// =============================================================================
    .global nar_gain_apply_neon
    .type   nar_gain_apply_neon, %function
nar_gain_apply_neon:
    // ── Early exit ────────────────────────────────────────────────────────
    cbz     w1, .Lgain_ret

    // ── Broadcast scalar gain to a 4-wide vector ──────────────────────────
    // s0 = gain (in v0.s[0]).  dup replicates lane 0 to all four lanes.
    dup     v16.4s, v0.s[0]           // v16.4s = {gain, gain, gain, gain}

    // ── Main loop: 16 samples per iteration ───────────────────────────────
    lsr     w2, w1, #4                // w2 = samples / 16
    cbz     w2, .Lgain_tail4

.Lgain_loop16:
    // Load 4 × 16-byte (= 64-byte / 16-float) block
    ldp     q17, q18, [x0]           // q17 = data[0..3],  q18 = data[4..7]
    ldp     q19, q20, [x0, #32]      // q19 = data[8..11], q20 = data[12..15]

    fmul    v17.4s, v17.4s, v16.4s   // multiply all 4 lanes by gain
    fmul    v18.4s, v18.4s, v16.4s
    fmul    v19.4s, v19.4s, v16.4s
    fmul    v20.4s, v20.4s, v16.4s

    stp     q17, q18, [x0]           // store back 8 floats
    stp     q19, q20, [x0, #32]      // store back 8 floats
    add     x0, x0, #64              // advance pointer 64 bytes = 16 floats
    subs    w2, w2, #1
    b.ne    .Lgain_loop16

    // ── Tail-4 loop: 0–12 remaining samples in groups of 4 ───────────────
.Lgain_tail4:
    // bits[3:2] of the remainder (samples & 15) give 0–3 extra 4-chunks
    and     w2, w1, #15              // w2 = samples & 15  (remainder mod 16)
    lsr     w3, w2, #2               // w3 = remainder / 4  (0, 1, 2, or 3)
    cbz     w3, .Lgain_tail1

.Lgain_loop4:
    ldr     q17, [x0]                // load 4 floats
    fmul    v17.4s, v17.4s, v16.4s
    str     q17, [x0]                // store 4 floats
    add     x0, x0, #16
    subs    w3, w3, #1
    b.ne    .Lgain_loop4

    // ── Tail-1 loop: 0–3 remaining individual samples ─────────────────────
.Lgain_tail1:
    and     w2, w2, #3               // w2 = remainder & 3  (0, 1, 2, or 3)
    cbz     w2, .Lgain_ret

.Lgain_loop1:
    ldr     s17, [x0]                // load 1 float
    fmul    s17, s17, s0             // scalar multiply (s0 still = gain)
    str     s17, [x0]
    add     x0, x0, #4
    subs    w2, w2, #1
    b.ne    .Lgain_loop1

.Lgain_ret:
    ret
    .size   nar_gain_apply_neon, . - nar_gain_apply_neon


// =============================================================================
// nar_biquad_stereo_neon
//
// void nar_biquad_stereo_neon(
//     const float* coeffs,   // x0 → [b0, b1, b2, a1, a2]  (5 floats, 20 bytes)
//     float  x_l,            // s0  left  input sample
//     float  x_r,            // s1  right input sample
//     float* s1_l,           // x1  left  delay state 1  (read AND written)
//     float* s1_r,           // x2  right delay state 1  (read AND written)
//     float* s2_l,           // x3  left  delay state 2  (read AND written)
//     float* s2_r,           // x4  right delay state 2  (read AND written)
//     float* y_l,            // x5  left  output
//     float* y_r)            // x6  right output
//
// Processes LEFT and RIGHT channels SIMULTANEOUSLY through the same biquad
// coefficients using 2-lane NEON float vectors (v.2s = two float32 lanes).
//
// Implements the Transposed Direct Form II (TDF-II) recurrence:
//   y    = b0·x + s1
//   s1'  = b1·x − a1·y + s2
//   s2'  = b2·x − a2·y
//
// Both channels share the same {b0,b1,b2,a1,a2} coefficients but maintain
// INDEPENDENT delay states {s1, s2} — exactly matching how the C inline
// nar_biquad_process_sample() is called twice (once for L, once for R) in the
// loudness processor K-weighting loop.  This NEON version halves that cost.
//
// Register map (all caller-saved; no save/restore needed):
//   v0.2s  = {x_l, x_r}     after ins packing
//   v17.2s = {*s1_l, *s1_r} delay state s1, loaded then written back
//   v18.2s = {*s2_l, *s2_r} delay state s2, loaded then written back
//   v19.2s = {b0, b0}       coefficients broadcast to 2 lanes
//   v20.2s = {b1, b1}
//   v21.2s = {b2, b2}
//   v22.2s = {a1, a1}
//   v23.2s = {a2, a2}
//   v24.2s = {y_l, y_r}     computed output
//   v25.2s = {s1_l', s1_r'} updated delay state
//   v26.2s = {s2_l', s2_r'} updated delay state
// =============================================================================
    .global nar_biquad_stereo_neon
    .type   nar_biquad_stereo_neon, %function
nar_biquad_stereo_neon:
    // ── Pack {x_l, x_r} into a 2-lane NEON vector ────────────────────────
    // After AAPCS64 call: s0 = x_l (v0.s[0]), s1 = x_r (v1.s[0]).
    // ins inserts v1.s[0] into lane 1 of v0, so v0.2s = {x_l, x_r}.
    ins     v0.s[1], v1.s[0]

    // ── Broadcast each coefficient to both lanes via ld1r ────────────────
    // ld1r: load one float from memory and replicate to all lanes of the vector.
    ld1r    {v19.2s}, [x0]           // v19 = {b0, b0}
    add     x7, x0, #4
    ld1r    {v20.2s}, [x7]           // v20 = {b1, b1}
    add     x7, x0, #8
    ld1r    {v21.2s}, [x7]           // v21 = {b2, b2}
    add     x7, x0, #12
    ld1r    {v22.2s}, [x7]           // v22 = {a1, a1}
    add     x7, x0, #16
    ld1r    {v23.2s}, [x7]           // v23 = {a2, a2}

    // ── Load per-channel delay states ─────────────────────────────────────
    // ld1 {vD.s}[i], [xN] — load one float lane from memory address.
    ld1     {v17.s}[0], [x1]         // v17.s[0] = *s1_l
    ld1     {v17.s}[1], [x2]         // v17.s[1] = *s1_r  → v17.2s = {s1_l, s1_r}
    ld1     {v18.s}[0], [x3]         // v18.s[0] = *s2_l
    ld1     {v18.s}[1], [x4]         // v18.s[1] = *s2_r  → v18.2s = {s2_l, s2_r}

    // ── TDF-II recurrence — both channels execute in parallel ─────────────
    //
    // Step 1: y = b0·x + s1
    fmul    v24.2s, v19.2s, v0.2s    // v24 = b0 * {x_l, x_r}
    fadd    v24.2s, v24.2s, v17.2s   // v24 += s1  →  y = {y_l, y_r}
    //
    // Step 2: s1' = b1·x − a1·y + s2
    fmul    v25.2s, v20.2s, v0.2s    // v25 = b1 * x
    fmls    v25.2s, v22.2s, v24.2s   // v25 -= a1 * y   (fmls: D = D − N×M)
    fadd    v25.2s, v25.2s, v18.2s   // v25 += s2  →  new s1
    //
    // Step 3: s2' = b2·x − a2·y
    fmul    v26.2s, v21.2s, v0.2s    // v26 = b2 * x
    fmls    v26.2s, v23.2s, v24.2s   // v26 -= a2 * y  →  new s2

    // ── Write back updated delay states ───────────────────────────────────
    st1     {v25.s}[0], [x1]         // *s1_l = new s1_l
    st1     {v25.s}[1], [x2]         // *s1_r = new s1_r
    st1     {v26.s}[0], [x3]         // *s2_l = new s2_l
    st1     {v26.s}[1], [x4]         // *s2_r = new s2_r

    // ── Write outputs ─────────────────────────────────────────────────────
    st1     {v24.s}[0], [x5]         // *y_l
    st1     {v24.s}[1], [x6]         // *y_r

    ret
    .size   nar_biquad_stereo_neon, . - nar_biquad_stereo_neon


#endif  // __aarch64__
