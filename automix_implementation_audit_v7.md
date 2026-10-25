# AutoMix Implementation Audit — v7 (2026-10-25)

**Base:** branch `main` at `fbb2ca8`, working tree clean before this session.
**Scope:** the entire AutoMix pipeline — decode/input, DSP analysis (C), merge and planning (Dart), transition scheduling (Kotlin/Media3), fade/tone DSP (C/NEON), cache/invalidation, tests and CI.
**Constraints honoured:** fully offline, deterministic DSP only, no ML, no new dependencies, no new runtime services, no broad rewrite.

---

## 1. Executive summary

AutoMix is a mature, mostly well-layered system (v4–v6 audits already closed decoder EOS, JNI fail-open, target-boundary, scan-coordination and settings-validation issues). This session hunted for *accuracy* defects that are measurable with deterministic synthetic material, and found four:

1. **Every flux-derived timestamp was 60–90 ms early** because spectral-flux frames were stamped at the window start instead of the window centre + half hop. This biased **beat phase, phrase phase, and their consumers** (beat-grid seek, phrase lock, drop seek) by up to ~150 ms at low sample rates.
2. **Phrase (4-bar) detection was structurally unsound**: the grid was built from a *rounded integer* frame period (a 120 BPM four-bar loop was stretched 8.00 s → 8.17 s) and the score was a *single ODF frame* whose height depends on sub-window alignment. Result: real phrase accents were missed and **identical bars could fabricate a phrase phase** (measured: best/second = 909/505 at 128 BPM — passes both gates).
3. **The head beat/downbeat grid ignored the octave guard** that the rest of the merge already applied: a double-time (240 BPM) head estimate on a 120 BPM track kept a phase measured modulo 250 ms and was later replayed against a 500 ms grid — an offbeat reference for every beat-aligned seek.
4. **The native fade envelope and the Kotlin envelope disagreed by up to 6 dB** on the outgoing deck at the start of a fade (native applied the outgoing trim immediately; Kotlin ramps it over the first quarter). This path is currently *dormant* (`nativeFadeAvailable = false`, AM6-03), so it is a latent parity defect, not a live audio bug.

All four are fixed, cache schema bumped to v18, and regressions added for each. No ML, no dependencies, no architecture change.

---

## 2. Pipeline map (as inspected)

```
MediaStore file
  └─ Kotlin: AutomixAnalysisBridge → PcmDecoder (MediaCodec) → AutomixPcmDownsampler
       (Butterworth 2-pole LPF @ 0.45×output rate, then factor-2 boxcar → 22.05 kHz mono;
        center/side power accumulated for the vocal proxy; LFE excluded)
       └─ JNI (native_dsp_jni.c) → FFI Dart bindings (automix_native_io/_types.dart)
            └─ C: automix_analyzer.c
                 STFT (2048/512 Hann) → log-spectral flux ODF → tempo autocorrelation
                 → beat phase (bin-refined) → quarter tempo curve → HPCP chroma → key
                 → RMS/centroid/onset/vocal-proxy → structural cues → phrase grid
            └─ C: automix_planner.c (offline set planner, reference implementation)
  └─ Dart: AutomixService (segment merge, features cache v18, plan → MethodChannel target)
       engine.dart: cost blend (tempo/key/energy/seam/structure/momentum/vocal/chord),
       confidence blends, transition cue (fade, gamma, trims, pitch, bass/mid/high overlap)
  └─ Kotlin: Media3PlaybackService (target maps, beat seek, early handover resolver,
       tempo nudge, tone manager) → CrossfadeController (16 ms tick, AutomixGainEnvelope
       fallback, phase lock, phrase lock, bass swap, tail filter) → Media3 dual players
       └─ AutomixToneAudioProcessor → C tone DSP (3-band EQ, crossfade envelope,
          true-peak limiter; ARM64 NEON stereo path + portable C fallback)
  Live: automix_live_tracker.c (streaming beat/downbeat phase, seqlock state)
```

Verified by reading: `automix_analyzer.c`, `automix_planner.c`, `automix_tone_processor.c`, `automix_phase_lock.c`, `automix_live_tracker.c`, `automix_native.h`, Dart `service.dart`/`engine.dart`/`models.dart`, Kotlin `AutomixAnalysisBridge`, `AutomixPcmDownsampler`, `AutomixGainEnvelope`, `AutomixTransitionPolicy`, `AutomixToneManager`, `CrossfadeController` (fade tick path), `Media3PlaybackService` (transition/seek paths), CI workflows.

**Not inspected end-to-end (declared, not claimed):** Signalsmith Stretch processor internals, JNI bridge symbols, Media3 audio-processor ordering at runtime, `native_audio_runtime/hook/build.dart` flag matrix, on-device timing.

---

## 3. Findings

| ID | Sev | Status | Area | Summary |
|---|---|---|---|---|
| AM7-01 | **P1** | **Fixed** | Analyzer timing | Flux frames stamped at window start → beat/phrase phase 60–90 ms early at every rate |
| AM7-02 | **P1** | **Fixed** | Phrase detection | Integer-rounded phrase grid (8.00 s→8.17 s at 120 BPM) + single-frame flux score → missed accents and spurious phrase phase |
| AM7-03 | **P2** | **Fixed** | Merge/head grid | Head beat/downbeat grid published across an octave fold that the tail/intro guards already reject |
| AM7-04 | **P2** | **Fixed** (latent) | Fade envelope parity | Native `compute_fade_gains` missing the outgoing-trim attack that Kotlin applies (≤6 dB step if enabled) |
| AM7-05 | **P2** | **Fixed** | Cache schema | Analyzer semantic change without a schema bump would have served stale phase/cue data |
| AM7-06 | P3 | Evaluated, not changed | Structural cues | Frame-start timestamp is correct for the RMS "after" window; the flux offset was reverted for them (measured: drop −77 ms, breakdown +11 ms) |
| AM6-03 | P2 | Open (inherited) | Native fade | `nativeFadeAvailable = false`: C/NEON envelope never runs in production |
| AM6-07 | P2 | Open (inherited) | Replan latency | serial `statSync`/JSON/loudness work during replan |
| AM7-07 | P3 | Open | Toolchain | Kotlin/Gradle suite and FFmpeg envelope regression cannot run in this workspace (no Android SDK, no ffmpeg) |
| AM7-08 | P3 | Open | Repo hygiene | `pubspec` was 1.5.47 while the newest changelog entry was 1.5.44 (pre-existing); added 1.5.48 on top rather than rewriting history |

### Confirmed root causes and evidence

**AM7-01 — flux timestamp.** The STFT frame covers `[f·hop, f·hop+FFT)` but positive log-spectral difference reports energy *entering* the window; the backward difference spans one hop. Stamping at the frame start therefore reports the onset up to ~2.5 hops early (≈60–90 ms at 22.05 kHz, worse at 16 kHz). Fix: `ODF_TIMESTAMP_OFFSET_SAMPLES = (FFT_SIZE + HOP_SIZE)/2`, folded modulo the beat period so phase stays inside `[0, period)`.

*Measured (synthetic click trains, phase error vs. known 137 ms offset):* after fix the residual is **−8.0 … +3.2 ms across 16/22.05/24/44.1/48 kHz** (probe run during the audit); before the fix the error was 60–90 ms and rate-dependent. Regression: `test_analyzer_beat_phase_timestamp` (5 rates × 2 tempi, `error < 12 ms`).

**AM7-02 — phrase grid and score.**
*Grid:* `round(fps·60/bpm)·16` frames stretched the four-bar phrase by 170 ms at 120 BPM (22-frame rounding); over a 48 s window that is several frames of drift, enough to hide an accent or to fake one from window-edge truncation. Fix: evaluate the grid in fractional milliseconds from `60000/bpm`, require ≥3 whole phrases in the window, require ≥3 observations per candidate.
*Score:* one ODF frame per candidate was replaced by **mean frame power over the whole beat interval** (alignment-insensitive; adjacent intervals disjoint). The 1.12× winner gate alone is unsafe: a bar conflict check (must beat the other three bar positions by ≥10 %) was added so a 4-beat accent pattern can never publish a phrase phase.

*Measured (48 s synthetic loops at 22.05 kHz):*

| case | flux score (old) | power score (new) | published? |
|---|---|---|---|
| accent every 16 beats, 128 BPM | best 0.0078 / 2nd 0.0010 | best 5.1× runner-up | yes, phase error < 25 ms |
| identical 4-beat bars, 128 BPM | best 909 / 2nd 505 (ratio 1.80, **no bar conflict**) | best 0.0083 / 2nd 0.0077 (ratio 1.08, **bar conflict**) | old: yes (spurious); new: suppressed |
| identical 4-beat bars, 90/120/127.3/140 | gate could pass | tie within 10 % + bar conflict | suppressed |

Detection margin with the new metric: accent beats score 0.0057–0.0088 vs 0.0007–0.0013 for non-accent bar positions (5–9×), versus 1.2–1.8× and noisy with single-frame flux.
Regression: `test_analyzer_phrase_phase_fractional_grid` (5 tempi × accent-16 must detect; 5 tempi × accent-4 must stay `NaN`).

**AM7-03 — head grid octave guard.** `automixMergeSegments()` already guarded `introBeatOffsetMs` and `tailBeatOffsetMs` with `edgePhaseSurvivesFold()`, but published the raw `beatOffsetMs`/`downbeatOffsetMs` of the first segment, which Media3 turns into the beat-grid seek for early handover. A head window detected at a *faster* octave than the published track tempo has a phase measured modulo a shorter period; replaying it against the longer period can reference an offbeat. Fix: same guard + confidence floor, phases still expressed in absolute file time. Two new merge tests (slower octave keeps the grid; faster octave drops it).

**AM7-04 — native fade trim attack.** `AutomixGainEnvelope.gains()` ramps `outgoingTrim` in over the first quarter (`attack = t/0.25`) while the C `nar_automix_tone_compute_fade_gains()` applied `trim_out` immediately; with a level-match trim of 0.4 that is a 6 dB difference at `t=0`. Fix mirrors the Kotlin formula exactly. Regression added in `test_native_crossfade_curve` (gains at t=0, 0.1, 0.25 with trim 0.4). **This path is dormant** (`nativeFadeAvailable = false`), so production behaviour is unchanged; the fix prevents a step at the moment AM6-03 is enabled.

**AM7-05 — cache schema.** Beats/phrase/drop cues changed semantics, so `_analysisSchemaVersion` 17 → 18 (all three readers compare per entry, and `_migrateAnalysisSchema()` resets the analyzed count). Regression: a v18→v17 invalidation test added next to the existing v8 test; two fixtures updated (the file documents that the literal must track the private constant).

### Structure cues (evaluated, deliberately not changed)

`raw_drop_ms`/`raw_breakdown_ms` derive from the **RMS** "after" window, which begins at the frame start — no flux lead applies, so the timestamp offset was reverted for them. Re-measured after the revert: drop cue **4922.6 ms** vs truth 5000 (−77 ms), breakdown **8010.9 ms** vs 8000 (+11 ms), both inside the existing regression windows (4400–5700 / 7300–8800) and far below a beat, after which Media3 snaps the seek to the incoming grid. The residual bias comes from the detector's asymmetric before/after windows, not the timestamp; changing it would move the error, not remove it — not worth the regression risk.

---

## 4. Changes actually implemented

| File | Change |
|---|---|
| `native_audio_runtime/src/automix_analyzer.c` | `ODF_TIMESTAMP_OFFSET_SAMPLES`; phase folded onto the beat period; fractional-ms phrase grid with ≥3-phrase window and ≥3 observations/candidate; beat-interval power scoring; bar-conflict gate; docs comment scoped to flux-derived outputs |
| `native_audio_runtime/src/automix_tone_processor.c` | outgoing-trim attack quarter in `compute_fade_gains`, matching Kotlin |
| `native_audio_runtime/test/automix_native_c_test.c` | `render_accented_click_train`, `circular_phase_error_ms`, `test_analyzer_beat_phase_timestamp`, `test_analyzer_phrase_phase_fractional_grid`, trim-attack assertions in `test_native_crossfade_curve` (58 → 60 test functions) |
| `lib/services/automix_service/engine.dart` | head beat/downbeat grid gated by `edgePhaseSurvivesFold` + confidence |
| `lib/services/automix_service/service.dart` | analysis schema 17 → 18 with rationale comment |
| `test/services/automix_service/automix_engine_test.dart` | 2 merge tests for the head-grid guard |
| `test/services/automix_service/automix_cache_test.dart` | fixtures → v18; new v17 invalidation test |
| `lib/pages/settings_page/changelog_data.dart` | 1.5.48 entry (5 bullets) |
| `pubspec.yaml` | 1.5.47 → 1.5.48 (matches new top changelog entry) |

Nothing else was touched; no generated files, no dependency or build-flag changes, no Kotlin/Java changes, no new files left in the tree (temporary C/Dart probes were deleted).

---

## 5. Improvements evaluated but **not** implemented

- **Turning on the native fade (AM6-03).** Requires a shared fade epoch across two physical streams and on-device capture; flipping `nativeFadeAvailable` is explicitly forbidden by the v6 audit. The envelope is now parity-correct so the flip is a smaller step later.
- **Higher-order anti-alias filter in `AutomixPcmDownsampler`.** The existing 2-pole Butterworth at 0.45×output + boxcar leaves ≈−7 dB at 15 kHz when decimating 44.1→22.05 kHz. A 4th-order cascade would improve it, but Kotlin tests cannot run in this workspace (no Android SDK), so the change would ship unverified.
- **Global tuning-offset estimation for key detection.** HPCP already uses a ±0.5-semitone raised-cosine window with harmonic folding, so ±50 cent detune lands on the correct class; a tuning estimator would mostly matter beyond that, with no measured deficiency.
- **Re-tuning the L1 headroom scale (3 dB mid-fade dip).** Intentional anti-clipping policy, documented in both implementations; changing it without a limiter design would trade clipping risk for loudness.
- **Structural-cue window asymmetry.** See above: measurement shows ~±45 ms, absorbed by beat snapping.
- **Replan latency (AM6-07) and C→NEON micro-optimizations.** No profile was captured on the target device; optimizing blind would be speculative (and Phase 4 forbids benchmark claims without measurements).

---

## 6. Tests executed and results

| Suite | Command | Result |
|---|---|---|
| Native C suite (60 cases) | `clang -O2 -std=c11 … automix_native_c_test.c + automix_{analyzer,live_tracker,phase_lock,planner,tone_processor}.c` | **exit 0** |
| Native C suite under sanitizers | same with `-fsanitize=address,undefined -fno-sanitize-recover` | **exit 0**, no ASan/UBSan reports |
| Native Dart suite | `cd native_audio_runtime && dart test` | **65/65 passed** |
| AutoMix Dart suites | `flutter test --no-pub test/services/automix_service` | **130/130 passed** (incl. 4 new) |
| Full Flutter suite | `flutter test --no-pub` | **280/280 passed** |
| Static analysis | `flutter analyze --no-pub --no-fatal-infos lib test` | **No issues** |
| Temporary measurement probes | compiled with clang, run, deleted | phase bias ±8 ms; phrase scores table above |

**Not run here (environment limits, not failures):**
- Kotlin/Gradle unit tests: no Android SDK (`ANDROID_HOME` unset) — Kotlin sources were not modified, so exposure is limited.
- `tools/automix_ffmpeg_regression.sh`: `ffmpeg`/`ffprobe` absent.
- Device/APK build and Mi 9T AudioFlinger capture: no NDK/emulator.
- CI is `workflow_dispatch` only; no run was triggered.

---

## 7. Before / after metrics

| Metric | Before | After |
|---|---|---|
| Beat-phase residual error (click train, 5 rates) | 60–90 ms early, rate-dependent | −8.0 … +3.2 ms |
| Phrase grid drift at 120 BPM over one 4-bar loop | +170 ms | 0 (fractional period) |
| Phrase accent detection, 90–140 BPM, accent-16 | missed at some tempi, mis-phased at others | 5/5 detected, phase error < 25 ms |
| Spurious phrase phase on identical bars (accent-4) | reproducible at 128 BPM (909 vs 505, no conflict) | suppressed (1.08 ratio + bar conflict) |
| Native vs Kotlin fade gain at t=0, trim 0.4 | 6 dB apart | identical (asserted) |
| Structural cues (unchanged behaviour) | — | drop −77 ms, breakdown +11 ms |

---

## 8. Remaining risks and untested behaviour

1. **Native fade still dormant** — the parity fix is test-covered but never runs on a device; enabling it remains the single largest unvalidated audio change.
2. **Phrase/beat timing on real recordings** — all evidence is synthetic (click trains, amplitude ramps). Real music has syncopation, rubato and percussion-dense sections; the new ≥3-observation and bar-conflict gates are conservative, but a field check on 10–20 reference tracks would confirm the false-positive rate.
3. **Kotlin layer not re-executed** — safe only because no Kotlin file changed; any future Kotlin edit needs the Gradle suite.
4. **On-device CPU/memory/underruns** — no measurement possible here; the changes add at most a few thousand `pow()` calls per analysis window (offline, not on the audio thread).
5. **`build/` symlink** to `/dev/shm/codebase-build` is an untracked scratch artifact of this workspace, not part of the repo.

---

## 9. Follow-up recommendations (benefit ▲ / risk ▶)

1. **Enable the native fade with a shared fade epoch** (AM6-03) — ▲▲ smoothness, less 16 ms volume traffic; ▶▶ needs cross-stream sync + device capture. Envelope parity is already done.
2. **Field-validate phrase locking on real tracks** — ▲▲ musicality; ▶ low (measurement only).
3. **4th-order anti-alias filter in the downsampler** — ▲ medium on percussion-heavy 44.1 kHz sources; ▶ low, but only once Gradle tests can run.
4. **Replan latency (AM6-07)** — ▲ medium on mid-range devices; ▶ low (cache/read only).
5. **NEON for the analyzer's FFT inner loop** — ▲ small (offline analysis, not on the audio thread); ▶ medium (needs parity tests). Lowest priority.