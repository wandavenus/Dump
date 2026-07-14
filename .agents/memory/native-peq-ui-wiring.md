---
name: Native PEQ wired to graphic EQ UI
description: How the Band EQ UI now routes gain through the native 32-band PEQ (dsp.peq) instead of the system Equalizer effect, and the interlock that keeps them from double-applying.
---

## Decision
The existing 5-band graphic EQ UI (`equalizer_page/band_slider.dart`, presets, room presets) now writes gain through `AudioEffectsService._writeEqBand()`, which picks the backend at call time:
- **Native PEQ** (`PlaybackManager.nativePeqAvailable` true) — each UI band maps 1:1 to a native PEQ band index as a `PeqFilterType.peak` filter at that band's reported center frequency (from `EqualizerParameters.centerFrequenciesHz`, extended for this purpose), Q=1.0.
- **System Equalizer** (native PEQ unavailable) — unchanged legacy path via `PlaybackManager.setEqualizerBandGain`.

**Why:** The native PEQ (Phase 5) is a real 32-band biquad EQ already running in the DSP pipeline but had zero UI wiring — the graphic EQ UI was still driving the lower-precision system/Media3 Equalizer effect exclusively.

**How to apply:** Never let both backends be active at once — they're in different signal layers and would double-apply gain. `setEqualizerEnabled`/init force `PlaybackManager.setEqualizerEnabled(false)` whenever the native path is used, and toggle `PlaybackManager.setNativePeqBypass` instead. Native PEQ coefficients need the current sample rate — `AudioEffectsService.setPeqSampleRateHint()` is fed from `audioFormatStream` in `audio_service/service.dart`, mirroring the existing Loudness Norm sample-rate sync pattern.

## Not done yet (future work if requested)
The UI still only exposes 5 bands with Peak-only filter type — the native PEQ's full range (32 bands, Q control, Shelf/Notch/Pass filter types) is still not user-facing. A dedicated "Advanced EQ" UI would be a separate, larger feature.
