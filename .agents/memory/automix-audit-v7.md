---
name: AutoMix implementation audit v7
description: Findings and verification evidence from the 2026-10-25 accuracy audit of the AutoMix analysis and transition pipeline.
---

Audit report: `automix_implementation_audit_v7.md` (repo root, per audit-output-convention).

Status:

1. **AM7-01 fixed — ODF timestamp.** Spectral-flux frames are stamped at frame centre + half hop (`ODF_TIMESTAMP_OFFSET_SAMPLES`), folded onto the beat period. Beat/phrase phases were 60–90 ms early before; residual is now ≤8 ms across 16/22.05/24/44.1/48 kHz. RMS-derived structural cues deliberately keep the frame-start stamp (their "after" window begins there) — do not "unify" the two timestamps.
2. **AM7-02 fixed — phrase grid + score.** 16-beat grid runs in fractional milliseconds (the old `round(fps*60/bpm)` stretched a 120 BPM four-bar loop 8.00→8.17 s) and each candidate is scored by mean frame *power* over the whole beat interval, not one ODF frame. Single-frame flux let identical bars differ by 1.8× purely from frame alignment and produced a spurious phrase phase at 128 BPM. A bar-conflict gate (must beat the other three bar positions by ≥10 %) plus ≥3 observations per candidate blocks 4-beat ambiguity.
3. **AM7-03 fixed — head grid octave guard.** `automixMergeSegments` now applies `edgePhaseSurvivesFold` + confidence floor to `beatOffsetMs`/`downbeatOffsetMs` (it already did for intro/tail grids). Faster-octave head phases are withheld because Media3 replays them against the longer track period.
4. **AM7-04 fixed (latent) — native fade trim attack.** `nar_automix_tone_compute_fade_gains` now ramps `outgoingTrim` over the first quarter exactly like `AutomixGainEnvelope.gains`; they differed by up to 6 dB at t=0. Path still dormant: `nativeFadeAvailable = false` (AM6-03 inherited, still open).
5. **AM7-05 — cache schema is v18.** Any future change to analyzer cue semantics requires another bump; note that `automix_cache_test.dart` hard-codes the version literal in two fixtures plus one invalidation test.

Verification in this environment: native C suite (O2 and ASan/UBSan) exit 0, `dart test` 65, `flutter test --no-pub test/services/automix_service` 130, full `flutter test` 280, `flutter analyze --no-pub lib test` clean. Kotlin/Gradle and `tools/automix_ffmpeg_regression.sh` cannot run here (no Android SDK, no ffmpeg) — Kotlin was left untouched for that reason.

Gotchas: repo has `build` → `/dev/shm/codebase-build` scratch symlink; `pubspec.yaml` (1.5.47) ran ahead of the newest changelog entry (1.5.44) before this session, resolved by adding 1.5.48 as the new top entry.