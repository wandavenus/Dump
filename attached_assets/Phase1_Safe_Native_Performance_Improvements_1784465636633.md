# Phase 1 — Safe Native Performance Improvements Only

## Objective

Implement **only the Phase 1 performance improvements** that are used frequently in real playback.

Focus on the hot paths that run often during normal listening.

---

## Hard Constraint

Do **NOT** allow any change in audio quality.

If a proposed optimization could change audio quality, then:

1. Look for a better alternative first.
2. If no safe alternative exists, **skip that item entirely**.
3. Do **not** force the optimization.

This is a performance-only pass, not a fidelity tradeoff pass.

---

## Priority Order

Work only on the frequently used items from the audit:

1. **Limiter**
2. **Soft Clipper**
3. **Stereo Widening**
4. **Compressor gain multiply**
5. **Crossfeed stereo matrix**

Do **not** spend time on low-frequency or optional items unless they are directly needed for the above.

---

## What to Implement

### 1) Limiter
Target the per-sample hot path in the limiter.

Goals:
- Reduce CPU cost
- Preserve exact output behavior
- No audible change
- No change in limiter character
- No change in timing or look-ahead semantics

If a vectorized or native rewrite risks changing behavior, keep the exact math or skip that part.

---

### 2) Soft Clipper
Optimize the soft clipper only if the output remains perceptually identical.

Rules:
- No changed clipping curve unless it is mathematically equivalent or demonstrably inaudible
- If approximation introduces even a small audible difference, do not use it
- Prefer exact or near-exact alternatives
- If no safe alternative exists, skip it

---

### 3) Stereo Widening
Move the heavy per-sample widening math onto the most efficient safe path.

Rules:
- Do not alter the stereo image character
- Do not change the mix balance
- Do not change PCM output quality
- If JNI/native migration adds risk or complexity without clear benefit, skip it

---

### 4) Compressor Gain Multiply
Optimize only the gain application path if it is exact.

Rules:
- Gain scaling must remain bit-for-bit equivalent or as close as practically possible without audible change
- Do not modify compression curve, attack, release, knee, or threshold behavior
- Do not change envelope logic
- If only the multiply loop can be improved safely, do that and nothing else

---

### 5) Crossfeed Stereo Matrix
Optimize the stereo matrix step only if it is mathematically identical.

Rules:
- No change to crossfeed tone
- No change to stereo width perception
- No change to phase behavior
- No change to output balance
- If the safe path is not clearly better, skip it

---

## Non-Goals

Do **NOT** touch:

- UI
- MediaSession
- Notifications
- Audio Focus
- Queue logic
- Shuffle
- Repeat
- Crossfade timing
- ReplayGain logic
- Loudness logic
- Lyrics
- Palette / artwork
- Shader / fluid background
- Any low-priority audit item

---

## Decision Rule

For each candidate, classify it as one of:

- **Implement now**
- **Implement with exact-equivalent behavior**
- **Skip**

Only implement items that are either:
- exact-equivalent, or
- clearly safe with no audio quality change.

If there is any uncertainty about audio quality, skip the item.

---

## Required Deliverables

Return:

1. **Which items were changed**
2. **Which items were skipped**
3. **Why each skipped item was skipped**
4. **Exact files modified**
5. **Exact lines changed**
6. **Confirmation that audio quality is unchanged**
   - or, if not possible, a clear explanation of why the item was skipped

---

## Verification

Before finishing, verify:

- audio quality is unchanged
- playback behavior is unchanged
- no new artifacts or distortion
- no regressions in frequently used paths
- no build or lint errors

---

## Implementation Philosophy

This phase is about **safe wins only**.

Better to leave a hotspot untouched than to gain speed by shaving audio fidelity.