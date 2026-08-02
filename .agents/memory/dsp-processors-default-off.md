---
name: DSP processors default off
description: User-configurable native DSP processors must start bypassed and receive explicit persisted settings from Dart.
---

# DSP processors must default off in Dart even if native default is on

User-configurable native DSP processors (`comp_processor.c`,
`limiter_processor.c`, `soft_clipper_processor.c`, `crossfeed_processor.c`)
must initialize with `bypass=1`. Their parameter defaults are audible, so the
native layer itself must be safe before Dart settings synchronization completes.

**Why:** the user does not want any DSP/audio feature altering audio
automatically without explicit opt-in. The Media3 service is created on-demand,
so playback can begin before Dart finishes pushing persisted settings.

**How to apply:** any new native DSP processor exposed via `PlaybackManager`
must start bypassed in C, have a Dart-side setting default of `false` or unity,
and receive an unconditional startup sync from
`AudioEffectsService._pushEngineSettingsWhenReady()`. Keep this native
fail-safe even if the startup order changes. PEQ is transparent by default
because `band_count=0` regardless of its bypass flag.
