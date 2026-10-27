---
name: AArch64 NEON differential regression
description: tools/neon_diff_regression.sh executes the four NEON kernels under qemu (or natively on arm64) and compares them bit-exactly; fused vs non-fused instruction shape is part of the contract.
---

# AArch64 NEON Differential Regression

## Why it exists
NEON is selected at compile time (`#if defined(__aarch64__)`) and the `.S` files
carry the same guard. On x86_64 hosts they become empty translation units, so
`dart test` and `flutter test` never execute a single NEON instruction — an
assembly bug would only surface on-device.

## Pieces
- Harness: `native_audio_runtime/tool/neon_diff_test.c` — freestanding (no libc/libm, raw syscalls only), compiled **only** for AArch64.
- Runner: `tools/neon_diff_regression.sh` — arm64 host builds natively; other hosts cross-compile with clang and execute under `qemu-aarch64-static`.
- CI: `.github/workflows/neon-diff.yml` (`workflow_dispatch`, like every other workflow).
- Coverage: `nar_gain_apply_neon`, `nar_biquad_stereo_neon`, `nar_automix_window_rms_neon` (n=256/1024/2048), `nar_automix_tone_process_stereo_neon` (frames 1/2/3/64/128 plus the `frames <= 0` guard), including NaN/±Inf/out-of-range sanitize and the ±1 clamp.

## The rule that matters
References mirror each kernel's **exact instruction shape**, because that shape is
part of the contract:

- `nar_biquad_stereo_neon` — step 1 `fmul` + `fadd` (non-fused); steps 2–3 `fmls` (fused).
- `nar_automix_window_rms_neon` — four independent fused lanes (`fmla`) reduced by `faddp`/`faddp`; returns the **power sum**, not RMS (the caller takes the square root).
- `nar_automix_tone_process_stereo_neon` — `fmla` in the one-pole filters and the band mix, but `fmul` + `fadd` for the 20 ms gain smoothing.

A plain multiply/add reference is therefore **not** equivalent: for the stereo
biquad at PCM level it diverges by up to ~1.1e-6 (~19 × 2⁻²⁴, ≈ −119 dBFS) after
5000 recursive steps. So:

- Never assert bit-equality between the NEON path and the portable C path across architectures.
- Compile the harness with `-ffp-contract=off`; explicit `__builtin_fmaf` calls still emit `fmadd`.

## Gotchas
- `lld` is usually installed versioned (`ld.lld-14`), never as bare `ld.lld`; the script searches for it and passes `--ld-path=<binary>` instead of `-fuse-ld=lld`.
- Debian/Ubuntu x86 prerequisites: `apt-get install -y clang lld qemu-user-static`.
- The harness is excluded from the Dart analyzer via `native_audio_runtime/tool/**` in `analysis_options.yaml`, and it `#error`s when compiled for a non-AArch64 target.
- Proof that it can fail: replacing a fused `fmls` in `neon_kernels.S` with `fmul` + `fsub` makes it report `FAILURES: 10000` and exit 1.
