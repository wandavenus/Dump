---
name: AutoMix implementation audit v6
description: Findings and follow-up priorities from the 2026-10-24 whole-system AutoMix audit.
---

Audit report: `automix_implementation_audit_v6.md`.

Current status and remaining priorities:

1. **Fixed:** `PcmDecoder` now separates input EOS from output EOS and only reports `onEos` after the output EOS buffer is drained; regression coverage is in `PcmDecoderTrimTest`.
2. **Fixed:** all `AutomixToneAudioProcessor` JNI entry points catch `LinkageError`; `AutomixToneNativeAvailability` latches tone processing off process-wide so an incompatible `.so` fails open. Latch coverage is in `AutomixToneNativeAvailabilityTest`.
3. **Fixed:** native AutoMix transition application now uses the same first-two-target list for validation and metadata storage; regression coverage is in `Media3PlaybackServiceAutomixBoundaryTest`.
4. **Fixed:** hydrated/copy-with `AutomixSettings` reject malformed, non-finite, fractional, and extreme tolerance/beat values; invalid values return to defaults. Coverage is in `automix_settings_test.dart`.
5. **Fixed:** `analyzeLibrary()` now refuses to start while the idle sweep owns the decoder/progress state; a deterministic race harness is still desirable for the timer/power-state path.
6. **In progress:** the former hard-coded `nativeFadeAvailable=false` path is now wired to the separate timeline-safe `AutomixFadeAudioProcessor` on both decks, with configuration and first-process proof before activation. Device/build validation remains open; see `native-automix-fade.md` and `docs/native-automix-fade-audit.md`.
7. `P2`: reduce serial synchronous stat/cache work in the replan path.

Local verification after the fixes: full Android unit tests, Kotlin compilation, AutoMix Dart tests, Dart analyzer, native Dart suite, standalone native C fade regression, debug/release ARM64 APK builds, release-symbol inspection, and `git diff --check` pass. Representative benchmark and device-level Mi 9T/AudioFlinger capture remain open.
