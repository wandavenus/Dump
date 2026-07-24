---
name: Native Palette Engine
description: androidx.palette MMCQ + custom perceptual selection replaces palette_generator_plus; covers channel name, selection algorithm, fallback chain, and migration notes.
---

## Rule
Use `NativePaletteService` (lib/services/native_palette_service.dart) for all palette extraction.
`PaletteExtractor` and `palette_generator_plus` have been fully removed.

## Channel
`dev.wndavenz.music/native_palette` — method `extractPalette(songId: Int)` → `List<Int>` (3 ARGB values)

## Native side
`NativePaletteBridge.kt` — androidx.palette MMCQ (maximumColorCount=32, clearFilters) + custom selectBestThree().
Reads artwork directly from ArtworkCacheManager (no bytes transfer over MethodChannel).
Registered in MainActivity.configureFlutterEngine → setupNativePaletteChannel().
Runs on artworkExecutor (bounded 2-thread pool).

## Selection Algorithm
1. Filter: sat ≥ 0.12, lightness 0.10–0.92
2. Score: sat^1.4 × lightnessFactor × (0.35 + 0.65 × popFactor)
3. Hue diversity: pick 3 with min hue dist, thresholds [40°, 25°, 12°, 0°]
4. Fallback: named palette swatches → hardcoded [0xFF2B313A, 0xFF4E657D, 0xFF7B8794]

## Dart Cache
LRU 256 entries + debounced disk persist to artwork/palette_cache.json (same path as old PaletteExtractor — cache survives migration).

**Why:** Dart palette_generator_plus had two problems: (1) Dart isolate overhead for decode+quantize, (2) naïve selection (swatches[0,1,2]) ignoring hue diversity and vibrance. Native approach eliminates both while keeping the same caching pipeline.

**How to apply:** Never re-add palette_generator_plus. If improving palette quality, extend selectBestThree() in NativePaletteBridge.kt — don't touch the Dart layer.

## Build dep
`androidx.palette:palette:1.0.0` added to android/app/build.gradle dependencies.
