# AutoMix benchmark corpus

`tools/automix_bench.dart` reads `manifest.json` and runs the native AutoMix
analyzer on each case. The checked-in cases are synthetic, deterministic
signals, so the repository does not ship copyrighted audio.

Run from the repository root:

```bash
dart run tools/automix_bench.dart
dart run tools/automix_bench.dart --check
dart run tools/automix_bench.dart --write-golden
```

## Adding real tracks

1. Put mono or stereo PCM16/float32 WAV files next to this manifest.
2. Add a case with `"kind": "file"` and a relative `"file"` path.
3. Fill in the labels the analyzer should be measured against:

```json
{
  "id": "real-track-001",
  "kind": "file",
  "file": "wav/real-track-001.wav",
  "expect": {
    "bpm": 124.0,
    "tonic": 9,
    "minor": true,
    "meter": 4,
    "beatOffsetMs": 137.0,
    "downbeatOffsetMs": 137.0
  }
}
```

Only include fields you have actually labeled. The harness reports unlabeled
fields as `-` rather than treating them as passes. For beat/downbeat labels,
`beatOffsetMs` is the phase of the first beat inside the file; the harness
compares it modulo the beat period. `downbeatOffsetMs` is compared modulo the
four-bar phrase.

## What the golden file gates

`golden.json` snapshots the analyzer's current output per case. `--check` fails
when a value moves outside a field-specific tolerance (tempo 2 %, dB fields
1.5 dB, phases 25 ms, structural labels exact). Regenerate it deliberately with
`--write-golden` after an intentional algorithm change, and review the diff.

This is a regression harness, not a perceptual quality benchmark. A 120-track
real-music corpus still needs to be supplied and labeled before tempo/key/metre
accuracy claims can be made.
