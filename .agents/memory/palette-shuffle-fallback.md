---
name: Palette fallback during shuffle
description: Native palette extraction and shuffle-aware artwork prefetch must distinguish transient failures from real palettes.
---

Native palette extraction must never report a transient missing-artwork or decode failure as a successful hardcoded fallback palette. Dart must not persist that fallback per song; otherwise a single race during a shuffle transition permanently masks the artwork palette.

**Why:** ExoPlayer shuffle can transition to a track outside the old linear prefetch window while `ArtworkCacheManager` is still extracting its WebP. Treating the temporary result as valid caused the player background to show fallback colours on later visits.

**How to apply:** Keep native failure results retryable, reject hardcoded fallback entries when warming or reading the palette cache, retry briefly in the background widget, and prefetch the native-reported `nextTrackIndex` rather than assuming the next list index.