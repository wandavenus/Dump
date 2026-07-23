---
name: DSP processors must default off in Dart even if native default is on
description: Compressor/Limiter/SoftClipper/Crossfeed native processors start bypass=false (active) at registration; Dart must explicitly bypass them until user opts in.
---

# DSP processors must default off in Dart even if native default is on

Several native DSP pipeline processors (`comp_processor.c`, `limiter_processor.c`,
`soft_clipper_processor.c`, `crossfeed_processor.c`) initialize with
`bypass=0` (i.e. audibly active, with real default thresholds/ratios) the
moment they register in the pipeline — unlike ReplayGain and Loudness Norm,
which correctly start `bypass=1` in their own `_init()`.

**Why:** the user does not want any DSP/audio feature altering audio
automatically without explicit opt-in. A processor with `bypass=0` and a
non-transparent default (e.g. compressor threshold −20 dBFS ratio 4:1,
limiter ceiling −1 dBFS, soft clipper threshold −0.5 dBFS, crossfeed amount
0.3) will color real playback the instant the pipeline initializes, with no
UI ever having called anything.

**How to apply:** any new native DSP processor exposed via
`PlaybackManager` must have its Dart-side `ValueNotifier<bool> xEnabled`
default to `false`, and `AudioEffectsService._pushEngineSettingsWhenReady()`
must unconditionally push `setNativeXBypass(!xEnabled.value)` on every app
start — not just when the user toggles it — because the native default
cannot be trusted to be silent. PEQ is the exception: it stays transparent
by default because `band_count=0` regardless of its bypass flag.
