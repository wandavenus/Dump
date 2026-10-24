---
name: HEAD diff review 2026-10-24
description: Review commit b622c84 wiring native AutoMix fade.
---

Review report: `fade_audit.md`.

Findings:

- Native fade is after Signalsmith Stretch but maps media milliseconds directly
  to output PCM frames; playback speed/tempo correction therefore misaligns the
  envelope.
- `AutomixFadeManager.arm()` does not roll back a successful first arm when the
  second arm fails; the controller also skips reset when arm returns false,
  allowing native/Kotlin double application.
- Seek during an active native overlap updates only the active/incoming deck's
  timeline and can leave the outgoing plan active while the controller stays in
  native mode.

Checks recorded in the report: Gradle unit tests, Dart analysis/tests, host C
suite, ASan/UBSan C suite, and native fade syntax check passed. Physical Xiaomi
Mi 9T playback validation remains open.
