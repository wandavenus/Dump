---
name: Native Parametric EQ removed
description: Band EQ now uses only the legacy Android system Equalizer — native 32-band PEQ processor was fully removed from the DSP pipeline.
---

Native 32-band Parametric EQ (`dsp.peq`, `NativeParametricEq`, `PeqFilterType`) was
deliberately removed. The legacy Android system `Equalizer` effect
(`Media3PlaybackBridge` / `PlaybackManager.getEqualizerParameters` /
`setEqualizerBandGain`) is now the **sole** Band EQ backend — do not reintroduce
a dual-EQ backend or a `_useNativePeq`-style branch.

**Why:** simplification decision by the user after the system Equalizer's
silent-attach-failure bug (see `eq-silent-attach-failure.md`) was fixed; native
PEQ was found technically correct but was still removed to keep exactly one EQ
code path.

**How to apply:** `biquad_filter.c/.h` was kept (still used by
`crossfeed_processor.c` and `loudness_processor.c` — do not delete it again
assuming it's PEQ-only). Pipeline processor registration is a plain dynamic
array append (no fixed slot indices), so removing/adding a processor never
requires renumbering other processors' logic — only doc comments describing
typical order need updating. The Equalizer page UI was already fully driven by
the system EQ's real reported band count/frequencies via
`getEqualizerParameters()`, so it needed no changes.
