---
name: Bit-Perfect Mode design
description: App-wide "bypass every audio effect" master switch — snapshot/restore + UI-lock pattern used to implement it.
---

## Rule
A master audio-bypass toggle must live where it governs the whole app (Settings root), never inside a feature-specific page (e.g. Equalizer page), even though the Equalizer page is one of the things it must force off.

To make the bypass real rather than cosmetic:
1. Before forcing everything off, snapshot every affected feature's current value to persisted storage (not just in-memory) — an app restart while the mode is on must not lose the user's prior configuration.
2. Force-off by calling each feature's *existing* public setter (not by writing internal state directly), so every downstream side effect (native DSP bypass calls, mutual-exclusion logic like ReplayGain vs system LoudnessEnhancer) still fires correctly.
3. Visually lock (dim + ignore-pointer) every UI control for a bypassed feature while the mode is active, with a small inline explanation. Without this, users can still flip a slider that appears to do nothing (or worse, silently re-enables itself), which reads as a broken/gimmick feature.
4. On restore, re-invoke each feature's setter with the snapshotted value (don't just flip a raw flag) so derived state (e.g. "ratio > 1.0 implies enabled") stays consistent.

**Why:** the user explicitly distinguished this from a "gimmick" — it must genuinely stop every audio-altering code path in the app, not just the ones exposed on one settings page, and must not silently lose the user's prior settings.

**How to apply:** any new "master switch that suppresses N other independent settings" feature — snapshot-before-force + reuse-existing-setters-to-restore + UI-lock-with-explanation is the reusable shape, regardless of domain.
