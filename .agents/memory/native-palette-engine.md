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
2. Score: 70% popFactor(log-scaled) + 30% vibrancy(sat^0.8) × lightFactor(peak L=0.50) × centerBoost(×1.15) × darkBonus(×1.20 if L<0.25); decode uses ARGB_8888.
3. Harmony triplet from top-24: maximize sum_scores × (1 + 0.5 × harmonyScore)
4. Roles: most saturated = accent; highest pop of rest = primary; remainder = secondary
5. **Neutral-dominance correction (Step 5b):** after triplet, check all swatches (unfiltered) for dominant neutral (S < 0.12, full lightness range). If neutral.population > primary.population × 2.0 → promote neutral to primary. This includes near-black and near-white artwork backgrounds without changing scoring or harmony selection.
6. Highlight/shadow: hue-coherent candidates from remainder; for neutral primaries (S < 0.12) skip hue-coherence check, derive directly from primary.
7. Fallback: named palette swatches → hardcoded colors

## Dart Cache
LRU 256 entries + debounced disk persist to the versioned palette cache file.
The cache was bumped to v6 for the extreme-neutral primary correction.

**Why:** Dart palette_generator_plus had two problems: (1) Dart isolate overhead for decode+quantize, (2) naïve selection ignoring hue diversity and vibrance. Native approach eliminates both.

**Why neutral-dominance fix:** saturation filter (S ≥ 0.10) correctly excludes achromatic noise from harmony triplet, but for artwork with neutral backgrounds + vivid logo it can leave only the logo colour to dominate the BG. The post-triplet neutral check restores the true background mood without breaking the chromatic harmony logic, including pure/near black and pure/near white.

**How to apply:** Never re-add palette_generator_plus. Extending selectBestFive() in NativePaletteBridge.kt is the correct extension point. Cache version must be bumped whenever the extraction algorithm changes meaningfully.

**Failure handling:** Native queue rejection and extraction exceptions are
returned as MethodChannel errors. Dart must not persist the fallback for these
transient failures; a normal successful extraction that legitimately has no
usable artwork may still return and cache the fallback.

## Build dep
`androidx.palette:palette:1.0.0` added to android/app/build.gradle dependencies.
