# AutoMix production wiring and implementation limits

This document records the production path verified during the follow-up audit for PR #179. It distinguishes live code paths from heuristic metadata and deferred features; a declared enum or unit-tested helper alone is not evidence that a feature affects playback.

## 1. Analysis path and ABI

1. Android `AutomixAnalysisBridge` decodes bounded head / middle / tail PCM windows through `AutomixPcmDownsampler`: a 2-pole Butterworth biquad low-pass runs at the source rate with cutoff $f_c = 0.45 \\times f_{output}$ before decimation. Stereo normally uses an L/R average, but falls back to the stronger channel when the mid signal is below 25% of the stronger channel to avoid near-total phase cancellation. It then calls `AutomixNative.nativeAnalyze`.
2. JNI (`automix_jni.cpp`) forwards the 21-value result contract from `nar_automix_analyze` in `native_audio_runtime/src/automix_analyzer.c`, including explicit `tailBpmConfidence` (index 20).
3. Kotlin maps the output slots to MethodChannel fields. The Dart parser `automixSegmentFeaturesFromAnalysisMap` validates types, finiteness, confidence ranges, key codes and cue offsets rather than silently dropping new fields.
4. `automixMergeSegments` aggregates valid windows and converts window-relative cue positions to file-absolute milliseconds. Vocal likelihood uses confidence-weighted aggregation; tail-only structure, breakdown, and `tailBpmConfidence` metadata are kept distinct from head metadata.
5. `AutomixService` persists these features using cache schema v11. Older entries are deliberately cache misses so legacy metadata cannot silently replace newly required fields.

The ABI tests enforce the exact 21-value analyzer output, invalid/undersized input behavior, valid confidence ranges, the structure-region enum range, and strict silence/noise expectations. Vocal likelihood is a **spectral proxy**, not voice isolation: it is confidence-gated and tonal/broadband-noise edge cases are tested.

## 2. Queue planning

The production planning path is:

`AutomixService.startAutomix → AutomixEngine.planSet → NativeAutomix.planSet → nar_automix_plan_set`.

The native planner receives 16 feature values per track, plus key and artist-group arrays. Its transition cost currently uses:

- confidence-weighted tempo compatibility and half/double-time variants;
- estimated key compatibility on the Camelot wheel;
- relative energy shaping across the planned set;
- artist repetition avoidance;
- vocal-conflict penalty only when both tracks have useful vocal likelihood and confidence.

The Dart reference scorer mirrors the native cost. Regression tests exercise high-confidence vocal clashes, a lower-confidence alternative, deterministic ordering and native/reference ordering parity.

**Limits:** key/Camelot compatibility is present; chord-progression analysis is not implemented. The vocal estimate is not an ML vocal detector or a source separator, so only confident estimates should influence order.

## 3. Transition decision to Media3 playback

After planning, `AutomixService` computes a cue per incoming track in `automixTransitionCue`. The result includes a strategy code, fade duration, curve, level trims and three-band overlap targets. The strategy selection is confidence-aware:

- `crossfade`: standard fade;
- `structureAligned`: align a fade to a reliable tail breakdown cue;
- `shortHandover`: shorten a confident tempo/key mismatch;
- `longBlend`: extend a sparse-tail/intro blend;
- `quickHandover`: shorten a dense-tail transition.

`_buildNativeTargets` sends those values through the `musicplayer/automix` MethodChannel. `Media3PlaybackService.applyAutomixTransitionNow` stores them by incoming song ID; `CrossfadeController` retrieves the target for the standby deck and applies the selected fade duration/curve during the actual two-player transition using an injectable `MonotonicClock` and real elapsed time calculation. Transition completion logic is protected by an `AtomicBoolean` single-execution guard to prevent race conditions during cancellations or delays.

Phrase alignment uses the offline beat/downbeat grids with current Media3 player positions.

## 4. Feature-driven EQ and overlap headroom

`automixTransitionCue` derives conservative attenuation-only targets from measured RMS-relative energy, onset rate, spectral centroid, structure metadata, and confidence-gated vocal overlap. `CrossfadeController` applies those targets during the overlap; `AutomixToneManager` keeps state per physical player slot; `AutomixToneAudioProcessor` passes controls to the native per-stream tone processor. The native processor smooths atomic target gains and splits bass/mid/high bands without making the audio callback acquire Kotlin locks.

Crossfade gain calculation in `CrossfadeController` applies a smooth ramp for `outgoingTrim` (starting at 1.0 at $t=0$ to prevent sudden volume drops) and releases `incomingTrim` smoothly to 1.0 at $t=1$. Combined equal-power gain is bounded to $\sqrt{2}$ ($\approx 1.414$), and effective target volume is evaluated dynamically on every callback tick. The scalar C path and ARM64 NEON path also clamp each stream's processed PCM sample to $[-1, 1]$. Native tests cover the overlap-gain budget and per-stream over-range sample clamp.

**Safety limit and dual-stream architecture:**
Two independent ExoPlayer instances process and output audio streams through separate AudioTracks, which Android AudioFlinger mixes downstream.
- **Headroom scaling:** Per-stream equal-power gain scaling ($G_{out}^2 + G_{in}^2 \le 1.0$) prevents overload for uncorrelated sources at the fader stage.
- **Per-stream sample clamp:** The native DSP pipeline clamps each stream's PCM samples to $[-1.0, 1.0]$.
- **Post-mix limitations:** Per-stream limiting does not guarantee that the downstream mixed sum of two correlated signals or signals with constructive phase alignment remains below $0\text{ dBFS}$, nor does sample clamping prevent inter-sample peaks (ISPs) during digital-to-analog conversion.
- **Shared software mix bus assessment:** Genuinely guaranteeing post-mix true-peak limits would require a single shared software mix bus with an oversampled true-peak limiter receiving PCM from both decoders prior to output.
No post-mix true-peak protection claim is made for the current dual-AudioTrack implementation; the verified guarantees are per-stream sample clamping and fader coefficient headroom bounds.

## 5. Reproducible SDK setup and validation

`setup-flutter.sh` resolves the official stable release manifest before deciding whether to reuse the workspace SDK. Reuse requires the version and a release stamp matching the official release hash and archive checksum; a new archive is SHA-256 checked against the manifest before extraction. Legacy un-stamped SDK copies are refreshed instead of trusted based on their self-reported version alone.

The PR verification workflow syntax-checks `setup-flutter.sh` and dispatches the Flutter analyzer/full test suite, focused AutoMix Dart/cache tests, native C/DSP tests with ASan/UBSan, Kotlin unit tests, and an Android ARM64 debug build. Test status is evidence only for the exact source SHA recorded in each run; the dispatch job succeeding means the linked jobs started, not that all of them passed.

## 6. Explicitly deferred functionality

- **Live PCM beat tracking:** deferred. Current phase/phrase correction uses offline grids and live player positions; it does not run a separate continuously adapting BPM/beat detector on the live PCM stream.
- **Chord progression:** not implemented. The existing harmonic planner uses estimated key/Camelot compatibility only.
- **True-peak limiting:** not implemented. The validated guarantee is a per-stream sample-peak clamp and bounded overlap gain budget only.

Those three features must not be presented as active capabilities until they have their own production path, failure-safe fallback and integration tests.
