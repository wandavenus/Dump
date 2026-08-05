---
name: Native Palette Engine
description: androidx.palette MMCQ + custom perceptual selection replaces palette_generator_plus; covers channel name, selection algorithm, fallback chain, and migration notes.
---

## Rule
Use `NativePaletteService` (lib/services/native_palette_service.dart) for all palette extraction.
`PaletteExtractor` and `palette_generator_plus` have been fully removed.

## Channel
`dev.wndavenz.music/native_palette` — method `extractPalette(songId: Int)` → `List<Int>` (5 ARGB values)

## Native side
`NativePaletteBridge.kt` — androidx.palette MMCQ (maximumColorCount=32, clearFilters) + custom selectBestFive().
Reads artwork directly from ArtworkCacheManager (no bytes transfer over MethodChannel).
Registered in MainActivity.configureFlutterEngine → setupNativePaletteChannel().
Runs on artworkExecutor (bounded 2-thread pool).

## Selection Algorithm (current)
1. Filter chromatic candidates: sat ≥ 0.10, lightness 0.06–0.93
2. Score: population-led score with vibrancy, lightness, center, and dark-tone factors; decode uses ARGB_8888.
3. Merge perceptually similar swatches with OKLab before role selection.
4. Coverage-driven roles: primary = largest family; secondary/accent = remaining families ranked by population plus perceptual distance from already-selected roles.
5. **Neutral-dominance correction:** after chromatic selection, a truly dominant neutral (S < 0.12, full lightness range) can replace primary. This includes near-black and near-white artwork backgrounds.
6. Highlight/shadow: use distinct remaining artwork clusters where possible, otherwise derive from primary.
7. Fallback: named palette swatches → hardcoded colors

## Dart Cache
LRU 256 entries + debounced disk persist to the versioned palette cache file.
The cache was bumped to v7 for coverage-driven role selection; v6 introduced
extreme-neutral primary correction.

**Why:** Dart palette_generator_plus had two problems: (1) Dart isolate overhead for decode+quantize, (2) naïve selection ignoring hue diversity and vibrance. Native approach eliminates both.

**Why neutral-dominance fix:** saturation filter (S ≥ 0.10) correctly excludes achromatic noise from harmony triplet, but for artwork with neutral backgrounds + vivid logo it can leave only the logo colour to dominate the BG. The post-triplet neutral check restores the true background mood without breaking the chromatic harmony logic, including pure/near black and pure/near white.

**Why coverage-driven roles:** a harmony-maximizing triplet can select several
related blue clusters and discard a real warm family such as skin or beige.
Role selection must preserve perceptually distinct, sufficiently populated
families before considering aesthetic harmony.

**How to apply:** Never re-add palette_generator_plus. Extending selectBestFive() in NativePaletteBridge.kt is the correct extension point. Cache version must be bumped whenever the extraction algorithm changes meaningfully.

**Failure handling:** Native queue rejection and extraction exceptions are
returned as MethodChannel errors. Dart must not persist the fallback for these
transient failures; a normal successful extraction that legitimately has no
usable artwork may still return and cache the fallback.

## Build dep
`androidx.palette:palette:1.0.0` added to android/app/build.gradle dependencies.
