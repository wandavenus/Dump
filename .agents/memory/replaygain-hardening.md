---
name: ReplayGain/loudness production-hardening pass
description: Key decisions from the BS.1770-4 hardening pass across the real-time loudness normalizer and the offline ReplayGain scanner/tag writer — read before touching either.
---

## Two separate loudness implementations — don't conflate them

- `native_audio_runtime/src/loudness_processor.c` (Dart FFI, host-testable): the
  **real-time playback-time** loudness normalizer. Runs in the live DSP
  pipeline (slot 2, gain→replaygain→**loudness**→peq→compressor→crossfeed→
  limiter→soft_clipper). Must be O(1)/causal, so it uses a documented
  approximation of the two-stage BS.1770-4 gating algorithm (100 ms sub-blocks
  in a ring forming 400 ms/75%-overlap blocks; absolute gate → relative gate →
  running integrated LUFS), not the offline two-pass spec algorithm.
- `android/app/src/main/cpp/replaygain/ebur128_analyzer.cpp` (Android NDK, not
  host-buildable): the **offline scanner** used when the user runs a
  ReplayGain scan to permanently tag files. Uses real libebur128
  (`EBUR128_MODE_TRUE_PEAK` etc.) — exact spec compliance, no
  causality constraint, this is the "real" two-pass algorithm.

**Why:** conflating these two led to wasted effort early on trying to make the
real-time processor spec-exact; it can't be, by design, without unbounded
look-ahead. The offline scanner is where spec-exactness actually lives, and
it was already correct before this hardening pass.

**How to apply:** if a bug report is about "measured LUFS looks off," ask
whether it's about the *live normalization* (loudness_processor.c) or the
*scan-and-tag* feature (ebur128_analyzer.cpp/tag_writer.cpp) — the fix
location and the acceptable-approximation bar are completely different.

## BS.1770-4 channel weighting: sum, don't average

Per-channel power must be **summed** with BS.1770-4 weights (front L/R/C =
1.0, surround/back = 1.41253754 [+1.5 dB power], LFE = 0.0), never divided by
channel count. Averaging was the historical bug in the real-time processor —
it made stereo read identically to mono at the same per-channel amplitude,
when spec-correct behavior is stereo reading ~3.01 dB louder (power doubles
when two identical channels are summed instead of averaged).

**How to apply:** a fast regression test for this bug class: feed identical
per-channel amplitude at N=1 vs N=2 channels and assert the measured
loudness differs by `10*log10(2) ≈ 3.0103 dB` — if it doesn't, some
channel-combining code path is averaging instead of summing.

## Crash-safe TagLib writes: temp-file + atomic rename

`TagLib::File::save()` rewrites its target in place and is not crash-safe on
its own. The established pattern (`tag_writer.cpp`'s `WithCrashSafeWrite`):
copy the original to a same-directory `<path>.rgtmp`, mutate/save only the
temp copy, then `std::rename()` it over the original only on full success;
on any failure, delete the temp file and leave the original untouched.
Same-directory is required so the rename is guaranteed same-filesystem
(atomic on POSIX).

**Why:** a kill/OOM/power-loss mid-`save()` could otherwise truncate or
corrupt a user's audio file's tag block.

**How to apply:** reuse this exact pattern for any future native code that
mutates a file in place (new tag fields, artwork embedding, etc.) rather
than calling a library's in-place save directly.

## Known gaps flagged but intentionally NOT fixed in this pass

- No cancellation support for `scanTrack`/`scanAlbum` (unlike
  `MetadataPrescanner.cancel()`) — a long album scan submitted to
  `replayGainScanExecutor` runs to completion even if the user navigates
  away; wasteful but not corrupting. Needs a cancel-token threaded through
  `PcmDecoder.decode()` → `ReplayGainService` → `ReplayGainBridge` →
  MainActivity method channel → Dart, which is a real feature addition, not
  a hardening fix.
- `PcmDecoder.kt` decodes to 16-bit PCM only (`EburAnalyzer::AddFramesFloat`
  exists but is unused/dead). Accepted as-is: 16-bit quantization noise
  (~-96 dBFS) is far below BS.1770-4 measurement tolerance, so this doesn't
  meaningfully affect loudness accuracy.
- Tag/file paths throughout ReplayGain (and the rest of the app) assume a
  direct POSIX filesystem path from `MediaStore.Audio.Media.DATA` — same
  constraint as `ExoMetadataReader`, not something ReplayGain introduced.
  Will not work for SAF-only (content://) access without a broader
  storage-access redesign.
