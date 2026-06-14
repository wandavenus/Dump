---
name: AndroidEqualizer presets
description: AndroidEqualizerParameters tidak punya .presets atau .setPreset(); preset diimplementasi manual di AudioEffectsService.eqPresets.
---

## Fakta
- `just_audio`'s `AndroidEqualizerParameters` hanya expose: `bands`, `minDecibels`, `maxDecibels`
- TIDAK ada `.presets` getter atau `.setPreset()` method
- Kalau kamu coba pakai `.presets` → compile error: `undefined_getter`

## Solusi
`AudioEffectsService.eqPresets` = `List<Map<String, dynamic>>` dengan field:
- `'name'`: String
- `'gains'`: `List<double>` (satu per band, urutan 60Hz→14kHz)

`AudioEffectsService.applyEqPreset(int index)` → iterate bands, clamp ke minDb/maxDb, panggil `band.setGain()`.

**Why:** just_audio wrapper tidak expose preset API Android yang ada natively karena presets di Android pun device-dependent dan tidak reliable.
