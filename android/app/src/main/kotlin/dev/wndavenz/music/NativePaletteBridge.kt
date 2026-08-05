package dev.wndavenz.music

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.palette.graphics.Palette
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Native color extraction bridge — replaces `palette_generator_plus`.
 *
 * Channel : "dev.wndavenz.music/native_palette"
 * Method  : "extractPalette" (arg: Int songId) → List<Int> (5 ARGB values)
 *
 * # Algorithm
 *
 * 1. **Artwork source** — reads the already-cached WebP via [ArtworkCacheManager].
 *
 * 2. **Image decode** — two-pass [BitmapFactory.decodeFile]: bounds-only first to
 *    compute the minimum power-of-two [inSampleSize] that keeps the decoded
 *    bitmap ≤ [PALETTE_TARGET_SIZE] px on each side.  Decoded as ARGB_8888 so
 *    soft artwork gradients do not acquire avoidable RGB_565 banding.
 *
 * 3. **MMCQ quantization** — [Palette.from] with [maximumColorCount] = 32 and
 *    no colour filters.
 *
 *
 * 5. **Perceptual scoring** — each swatch is scored:
 *      score = (0.70 × pop_factor + 0.30 × sat^0.8)
 *              × lightness_factor × center_boost × dark_bonus
 *    where:
 *      - pop_factor         = log(population+1) / log(maxPop+1)
 *      - sat                = HSL saturation
 *      - lightness_factor   = max(0.05, 1 − |lightness − 0.50| × 0.9)
 *      - dark_bonus         = 1.20 when lightness < 0.25, otherwise 1.0
 *      - center_boost       = 1.15 if color is prominent in center crop, else 1.0
 *
 * 6. **OKLab color clustering** — perceptually similar swatches are merged into
 *    [ColorCluster] groups using the existing OKLab [colorSimilar] function
 *    (threshold 0.15).  This corrects a fundamental weakness of MMCQ: a single
 *    visual color family (e.g. Black + Navy + Dark Blue) is often split into
 *    multiple Palette swatches, each covering a small fraction of the image.
 *    Without clustering, a 28 % skin tone wins over a 48 % dark family simply
 *    because the dark pixels are fragmented across three separate buckets.
 *    After clustering, the merged dark family competes with its full weight.
 *
 * 7. **Coverage-driven role selection** — roles are selected greedily from the
 *    highest-scoring clusters. Population remains the main signal, while
 *    perceptual distance from already-selected roles prevents three shades of
 *    the same blue from consuming the palette. This preserves real secondary
 *    families such as skin, beige, green, or red instead of inventing a
 *    mathematically harmonious substitute.
 *
 * 8. **Role assignment**:
 *      primary   = largest visual family
 *      secondary = largest remaining sufficiently different family
 *      accent    = most useful remaining coverage/diversity family
 *
 * 9. **Highlight + Shadow** — two extra colors from the remaining clusters:
 *      highlight = lightest saturated representative (L > 0.55, S > 0.10)
 *      shadow    = darkest saturated representative  (L < 0.45, S > 0.08)
 *    Derived from primary's hue if no suitable cluster exists.
 *
 * 10. **Output** — 5-element List<Int> [primary, secondary, accent, highlight, shadow].
 *     Existing callers that only read index 0/1/2 remain fully compatible.
 *
 * # Performance
 * The palette pass is intentionally bounded to a small bitmap. Clustering is
 * an O(n²) sweep over at most a few dozen swatches and role selection is linear
 * over the resulting clusters — negligible; no extra bitmap decoding or
 * Palette generation is required.
 * Timings depend on whether artwork is already cached: cache hits avoid
 * MediaStore extraction, while cache misses include artwork extraction and
 * WebP encoding in [ArtworkCacheManager].
 */
class NativePaletteBridge(
    private val artworkCacheManager: ArtworkCacheManager,
    private val executor: ExecutorService,
) {

    companion object {
        private const val TAG = "NativePaletteBridge"
        const val CHANNEL = "dev.wndavenz.music/native_palette"

        /**
         * 5-color fallback — index order matches the extended palette:
         *   0 primary, 1 secondary, 2 accent, 3 highlight, 4 shadow.
         * First 3 are identical to the old 3-color fallback for cache compat.
         */
        val FALLBACK: List<Int> = listOf(
            0xFF2B313A.toInt(),  // primary
            0xFF4E657D.toInt(),  // secondary
            0xFF7B8794.toInt(),  // accent
            0xFFABBED4.toInt(),  // highlight
            0xFF121821.toInt(),  // shadow
        )

        private const val PALETTE_TARGET_SIZE = 128

         /** Maximum scored clusters considered for coverage role selection. */
        private const val TOP_N = 32

        /**
         * Palette algorithm version — bump whenever the scoring / selection
         * logic changes so callers can invalidate stale cached results.
         * v8: preserves valid one/two-family palettes instead of falling back
         *     to AndroidX named swatches; two-family artwork keeps the second
         *     family as accent and derives a related secondary tone.
         */
        const val CACHE_VERSION = 8

        /** Minimum perceptual distance for a distinct palette role. */
        private const val MIN_ROLE_DISTANCE = 0.12f

        /** Maximum hue distance for non-neutral highlight/shadow candidates. */
        private const val HUE_ANCHOR_THRESHOLD = 120f
    }

    // ── Internal data models ─────────────────────────────────────────────────

    /** A scored swatch — score is the perceptual importance of this color. */
    private data class Scored(val swatch: Palette.Swatch, val score: Double)

    /**
     * A group of perceptually similar [Palette.Swatch] objects merged by
     * OKLab distance.
     *
     * Why clustering exists:
     *   Palette's MMCQ quantization splits visually identical or near-identical
     *   color families (e.g. Black + Navy + Dark Blue on the same dark
     *   background) into multiple separate swatches.  Each swatch covers only
     *   a fraction of the true color family's area, so it scores below a
     *   single contiguous bright region even when the dark family is actually
     *   more dominant.  Merging them restores the correct population weight.
     *
     * Why representative swatches instead of RGB averages:
     *   Averaging sRGB channels mixes gamma-encoded values, producing a color
     *   that may not appear in the artwork and whose perceived lightness is
     *   shifted.  The [representativeSwatch] is always a real Palette swatch —
     *   it is visually accurate, numerically stable, and carries the correct
     *   HSL values for downstream harmony and role-assignment calculations.
     */
    private data class ColorCluster(
        val swatches: MutableList<Palette.Swatch>,
        var totalPopulation: Int,
        var totalScore: Double,
    ) {
        /**
         * The swatch with the highest individual score within this cluster.
         * This is the color returned to Flutter and used for hue calculations.
         *
         * [mergeSimilarSwatches] iterates the pre-scored list in descending
         * score order, so the first swatch added to each cluster is always the
         * highest-scored one — no later entry can have a higher score.
         * The list is always non-empty by construction.
         */
        val representativeSwatch: Palette.Swatch
            get() = swatches.first()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Public entry point ────────────────────────────────────────────────────

    fun handleCall(method: String, args: Any?, result: MethodChannel.Result) {
        if (method != "extractPalette") {
            result.notImplemented()
            return
        }
        val songId = (args as? Int)
        if (songId == null || songId <= 0) {
            result.error("invalid_song_id", "extractPalette requires a positive Int songId", null)
            return
        }

        try {
            executor.execute {
                try {
                    val colors = extractColors(songId)
                    mainHandler.post { result.success(colors) }
                } catch (error: Exception) {
                    Log.w(TAG, "Palette extraction failed for songId=$songId", error)
                    mainHandler.post {
                        result.error(
                            "palette_extraction_failed",
                            error.message ?: "Palette extraction failed",
                            null,
                        )
                    }
                }
            }
        } catch (error: RejectedExecutionException) {
            Log.w(TAG, "Palette queue rejected songId=$songId", error)
            result.error("palette_busy", "Palette extraction queue is busy", null)
        }
    }

    // ── Core extraction pipeline ──────────────────────────────────────────────

    private fun extractColors(songId: Int): List<Int>? {
        // A missing/temporarily unavailable artwork is not a successful palette
        // extraction. Returning null lets Dart retry instead of persisting the
        // generic fallback as if it belonged to this song.
        val path = artworkCacheManager.getOrExtract(songId) ?: return null

        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

        var sampleSize = 1
        while (boundsOpts.outWidth / sampleSize > PALETTE_TARGET_SIZE ||
               boundsOpts.outHeight / sampleSize > PALETTE_TARGET_SIZE) {
            sampleSize *= 2
        }

        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: return null

        return try {
            val palette = Palette.from(bitmap)
                .maximumColorCount(96)
                .clearFilters()
                .generate()
            selectBestFive(palette)
        } finally {
            bitmap.recycle()
        }
    }

    // ── Colour selection (main) ───────────────────────────────────────────────

    /**
     * Selects 5 perceptually rich, visually harmonious colors from [palette],
     * using [bitmap] for center-crop spatial weighting.
     *
     * Returns [FALLBACK] only if no usable swatches are found.
     */
    private fun selectBestFive(palette: Palette): List<Int> {
        val all = palette.swatches
        if (all.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 1: Center-crop palette for spatial weighting.

        // Step 2: Filter achromatic swatches.
        val candidates = all.filter { sw ->
            val hsl = sw.hsl
            hsl[1] >= 0.10f && hsl[2] in 0.06f..0.93f
        }
        if (candidates.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 3: Score each candidate.
        //
        // Scoring philosophy (updated):
        //   Population is the PRIMARY driver — colors that cover large areas of
        //   the artwork should win, representing the overall mood/atmosphere.
        //   Saturation is a SECONDARY boost — vibrant colors get a moderate lift
        //   but can no longer overpower a dominant background with 24x advantage.
        //
        // Key changes from the old formula (sat^1.4 * lightFactor_steep):
        //   • Score = 70% population + 30% vibrancy(sat^0.8)
        //     → isolated saturated elements (hair, logo) no longer overwhelm
        //       large background areas (lavender, teal, cream)
        //   • lightFactor peak shifted 0.45→0.50, falloff reduced 1.6→0.9
        //     → lighter background tones (L≈0.65-0.80) are no longer heavily
        //       penalised — they now contribute meaningfully to the palette
        //   • centerBoost reduced 1.4→1.15
        //     → center subjects still get a small lift but can't dominate alone
        val maxPop = candidates.maxOf { it.population }.toDouble().coerceAtLeast(1.0)

        val scored = candidates.map { sw ->
            val hsl     = sw.hsl
            val sat     = hsl[1].toDouble()
            val light   = hsl[2].toDouble()
            // Wider lightness window: peak at L=0.50, gentle falloff.
            // Old: peak 0.45, falloff ×1.6 → heavily penalised light backgrounds.
            // New: peak 0.50, falloff ×0.9 → light/mid/dark all compete fairly.
            val lightFactor = (1.0 - abs(light - 0.50) * 0.9).coerceAtLeast(0.05)
            val popFactor   = log10(sw.population + 1.0) / log10(maxPop + 1.0)
            // Softer saturation power: sat^0.8 reduces the gap between
            // very saturated (0.85→0.88) and moderately saturated (0.25→0.32).
            val vibrancy    = sat.pow(0.8)
            // Blended score: dominant area (70%) + vibrancy (30%).
            val baseScore   = popFactor * 0.70 + vibrancy * 0.30

            val darkBonus = if (light < 0.25) 1.20 else 1.0
            val score = baseScore * lightFactor * darkBonus
            Scored(sw, score)
        }.sortedByDescending { it.score }

        // Step 4: OKLab clustering — merge swatches that are perceptually similar
        // before harmony selection.  This corrects MMCQ fragmentation: a single
        // dark-family background (Black + Navy + Dark Blue ≈ 48 %) would otherwise
        // lose to a 28 % skin tone because its pixels are split across three small
        // buckets.  After clustering, the merged family competes with its true weight.
        //
        // Clusters are sorted by totalScore (DESC) rather than raw population because
        // totalScore already encodes population, saturation, lightness, center
        // weighting, and dark bonus — preserving all the advantages of the scoring
        // formula across the merge boundary.
        val clusters = mergeSimilarSwatches(scored)
            .sortedByDescending { it.totalScore }

        // Step 5: Coverage-driven role selection from top-N clusters.
        //
        // The old harmony triplet could select three related blue clusters and
        // discard a meaningful warm family. Start with the largest family, then
        // deliberately reward perceptual distance for the next two roles.
        val top = clusters.take(TOP_N)
        if (top.isEmpty()) return buildFallbackFromPalette(palette)

        // Use the perceptual score for primary rather than raw population.
        // A dark navy family can have slightly fewer pixels than a skin/beige
        // family but still be the artwork's visual anchor because the score
        // includes lightness and dark-tone weighting.
        var primaryCluster = top.maxByOrNull { it.totalScore }
            ?: return buildFallbackFromPalette(palette)
        var secondaryCluster = chooseCoverageCluster(
            candidates = top,
            selected = listOf(primaryCluster),
            diversityWeight = 0.45,
        )
        var accentCluster = secondaryCluster?.let { secondary ->
            chooseCoverageCluster(
                candidates = top,
                selected = listOf(primaryCluster, secondary),
                diversityWeight = 0.70,
            )
        }

        // Step 6: Neutral-dominance correction.
        // The saturation filter (S ≥ 0.10) above intentionally discards near-
        // achromatic pixels so they don't pollute the chromatic triplet.  But
        // for artwork whose BACKGROUND is white, gray, or another near-neutral
        // tone (e.g. an album cover with a bright logo on a white/gray canvas),
        // those background pixels are the majority of the image — yet they were
        // all filtered out, leaving only the small saturated logo to dominate.
        //
        // Fix: after the chromatic triplet is chosen, find the most-populated
        // neutral swatch (S < 0.12) across the complete lightness range. This
        // includes pure/near black and pure/near white, which were previously
        // excluded by the 0.08..0.92 window. Compare its population against
        // the primary cluster's totalPopulation (which already accounts for
        // merged chromatic swatches) so an extreme neutral background can
        // correctly replace a colorful logo when it truly dominates.
        val dominantNeutral = all
            .filter { sw ->
                val hsl = sw.hsl
                hsl[1] < 0.12f && hsl[2] in 0.0f..1.0f
            }
            .maxByOrNull { it.population }

        if (dominantNeutral != null &&
    dominantNeutral.population > primaryCluster.totalPopulation * 2.0) {
    // The dominant neutral becomes the primary tone. Downstream highlight
    // and shadow derivation then uses this actual artwork tone as its anchor,
    // so black/white artwork is not forced through a chromatic triplet.
    primaryCluster = ColorCluster(
        swatches = mutableListOf(dominantNeutral),
        totalPopulation = dominantNeutral.population,
        totalScore = 0.0,
    )

            secondaryCluster = chooseCoverageCluster(
                candidates = top,
                selected = listOf(primaryCluster),
                diversityWeight = 0.45,
            )
            accentCluster = secondaryCluster?.let { secondary ->
                chooseCoverageCluster(
                    candidates = top,
                    selected = listOf(primaryCluster, secondary),
                    diversityWeight = 0.70,
                )
            }
        }

        // A Palette can legitimately contain only two distinct visual families
        // after perceptual clustering. Do not call buildFallbackFromPalette()
        // here: that named-swatch hierarchy often returns three related blues
        // and discards the real warm family. Keep the second family as accent,
        // and derive only the missing supporting blue tone.
        val primaryColor = primaryCluster.representativeSwatch.rgb
        val secondaryColor = when {
            accentCluster != null -> secondaryCluster!!.representativeSwatch.rgb
            else -> deriveSecondary(primaryColor)
        }
        val accentColor = when {
            accentCluster != null -> accentCluster!!.representativeSwatch.rgb
            secondaryCluster != null -> secondaryCluster!!.representativeSwatch.rgb
            else -> deriveAccent(primaryColor)
        }

        // Step 8: Highlight + Shadow from remaining clusters.
        //
        // Search remaining clusters using representativeSwatch for hue,
        // saturation, and lightness — the representative is what users see,
        // so it drives the hue-coherence check and light/dark threshold.
        // Candidates must be hue-coherent with the primary (within
        // HUE_ANCHOR_THRESHOLD degrees) to avoid visually unrelated tones
        // contaminating the palette gradient.  For neutral primaries (S < 0.12)
        // skip the hue-coherence check — achromatic hue is arbitrary in HSL;
        // derive directly from primary.  If no cluster qualifies, fall back to
        // deriveHighlight() / deriveShadow() unchanged.
        val usedRgbs = setOf(
            primaryCluster.representativeSwatch.rgb,
            secondaryCluster?.representativeSwatch?.rgb,
            accentCluster?.representativeSwatch?.rgb,
        ).filterNotNull().toSet()
        val restClusters = clusters.filter { it.representativeSwatch.rgb !in usedRgbs }
        val primaryHue     = primaryCluster.representativeSwatch.hsl[0]
        val primaryIsNeutral = primaryCluster.representativeSwatch.hsl[1] < 0.12f

        val highlightCluster = if (primaryIsNeutral) null else restClusters.filter { cl ->
            val hsl = cl.representativeSwatch.hsl
            hsl[2] > 0.55f && hsl[1] > 0.10f &&
                hueDist(hsl[0], primaryHue) <= HUE_ANCHOR_THRESHOLD
        }.maxByOrNull { it.representativeSwatch.hsl[2] }
        val highlightColor = highlightCluster?.representativeSwatch?.rgb
            ?: deriveHighlight(primaryCluster.representativeSwatch.rgb)

        val shadowCluster = if (primaryIsNeutral) null else restClusters.filter { cl ->
            val hsl = cl.representativeSwatch.hsl
            cl.representativeSwatch.rgb != highlightCluster?.representativeSwatch?.rgb &&
                hsl[2] < 0.45f && hsl[1] > 0.08f &&
                hueDist(hsl[0], primaryHue) <= HUE_ANCHOR_THRESHOLD
        }.minByOrNull { it.representativeSwatch.hsl[2] }
        val shadowColor = shadowCluster?.representativeSwatch?.rgb
            ?: deriveShadow(primaryCluster.representativeSwatch.rgb)

        return listOf(
            primaryColor,
            secondaryColor,
            accentColor,
            highlightColor,
            shadowColor,
        )
    }

    // ── OKLab color clustering ────────────────────────────────────────────────

    /**
     * Merges perceptually similar scored swatches into [ColorCluster] groups
     * using OKLab distance via the existing [colorSimilar] function.
     *
     * Algorithm: greedy O(n²) sweep — for each incoming swatch, find the first
     * existing cluster whose [ColorCluster.representativeSwatch] is within the
     * [colorSimilar] threshold (0.15 OKLab distance).  If found, merge into
     * that cluster; otherwise start a new cluster.
     *
     * Why OKLab over HSV or RGB Euclidean distance:
     *   OKLab's perceptual uniformity means "looks the same" corresponds to a
     *   small distance regardless of the RGB path — RGB fails for dark-similar
     *   (near-black navy vs near-black charcoal) and hue-similar-but-lightness-
     *   different pairs that RGB treats as far apart.
     *
     * The threshold 0.15 is defined inside [colorSimilar] and is not modified
     * here — it is the established calibration for this perceptual space.
     *
     * With at most [TOP_N] candidates the sweep is bounded to ≈ 576 comparisons:
     * no extra bitmap decoding or Palette generation is required.
     */
    private fun mergeSimilarSwatches(scored: List<Scored>): List<ColorCluster> {
        val clusters = mutableListOf<ColorCluster>()
        for (item in scored) {
            val existing = clusters.firstOrNull { cluster ->
    cluster.swatches.any { sw ->
        colorSimilar(sw.rgb, item.swatch.rgb)
    }
}
            if (existing != null) {
                existing.swatches += item.swatch
                existing.totalPopulation += item.swatch.population
                existing.totalScore += item.score
            } else {
                clusters += ColorCluster(
                    swatches = mutableListOf(item.swatch),
                    totalPopulation = item.swatch.population,
                    totalScore = item.score,
                )
            }
        }
        return clusters
    }

    /**
     * Chooses the next role by balancing visual coverage and perceptual
     * distance from roles that have already been selected.
     *
     * The first pass only considers genuinely different families. If the
     * artwork does not contain enough distinct families, the distance guard is
     * relaxed so the output still contains three valid colors.
     */
    private fun chooseCoverageCluster(
        candidates: List<ColorCluster>,
        selected: List<ColorCluster>,
        diversityWeight: Double,
    ): ColorCluster? {
        val selectedRgbs = selected.map { it.representativeSwatch.rgb }.toSet()
        val remaining = candidates.filter {
            it.representativeSwatch.rgb !in selectedRgbs
        }
        if (remaining.isEmpty()) return null

        val maxPopulation = remaining.maxOf { it.totalPopulation }
            .toDouble()
            .coerceAtLeast(1.0)

        fun rank(pool: List<ColorCluster>): ColorCluster? {
            return pool.maxByOrNull { cluster ->
                val area = log10(cluster.totalPopulation + 1.0) /
                    log10(maxPopulation + 1.0)
                val minDistance = selected.minOf { selectedCluster ->
                    perceptualDistance(
                        cluster.representativeSwatch.rgb,
                        selectedCluster.representativeSwatch.rgb,
                    )
                }
                val diversity = (minDistance / 0.25).coerceIn(0.0, 1.0)
                area * (1.0 - diversityWeight) + diversity * diversityWeight
            }
        }

        val distinct = remaining.filter { cluster ->
            selected.all {
                perceptualDistance(
                    cluster.representativeSwatch.rgb,
                    it.representativeSwatch.rgb,
                ) >= MIN_ROLE_DISTANCE
            }
        }
        return rank(distinct).takeUnless { it == null } ?: rank(remaining)
    }

    // ── Legacy harmony helpers ────────────────────────────────────────────────
    //
    // Kept local for backwards-readable diagnostics and future comparisons.
    // Role selection no longer calls these helpers because harmony alone can
    // discard a real warm family in favour of several related blue clusters.

    /**
     * From [clusters] (pre-sorted by totalScore), evaluates all combinations
     * of 3 and returns the triplet that maximises:
     *   sum_of_cluster_scores × (1 + 0.5 × harmony_score)
     *
     * Harmony calculations use [ColorCluster.representativeSwatch].hsl rather
     * than an averaged hue — the representative is the color users actually
     * see, so it must drive hue matching.
     *
     * At most [TOP_N] clusters → at most C(24,3)=2024 combinations: negligible
     * on the already downsampled palette bitmap.
     */
    private fun selectHarmoniousTriplet(clusters: List<ColorCluster>): List<ColorCluster> {
        val n = clusters.size
        // Fewer than 3 chromatic clusters → cannot form a meaningful triplet.
        // Return emptyList() so the caller falls back to buildFallbackFromPalette()
        // instead of receiving a 1- or 2-element list and collapsing all three
        // roles onto the same cluster.
        if (n < 3) return emptyList()

        var bestCombo = emptyList<ColorCluster>()
        var bestScore = -1.0

        for (i in 0 until n) {
            for (j in i + 1 until n) {
                for (k in j + 1 until n) {
                    val indivSum = clusters[i].totalScore +
                                  clusters[j].totalScore +
                                  clusters[k].totalScore
                    val harmony = harmonyScore(
                        clusters[i].representativeSwatch.hsl[0],
                        clusters[j].representativeSwatch.hsl[0],
                        clusters[k].representativeSwatch.hsl[0],
                    )
                    val total = indivSum * (1.0 + 0.5 * harmony)
                    if (total > bestScore) {
                        bestScore = total
                        bestCombo = listOf(clusters[i], clusters[j], clusters[k])
                    }
                }
            }
        }
        return bestCombo
    }

    /**
     * Scores a triplet of hues (0..360) for visual harmony.
     *
     * Returns a value in [0, 1] where:
     *   1.0 = perfect triadic or complementary relationship
     *   0.0 = near-monochromatic (spread < 25°)
     */
    private fun harmonyScore(h1: Float, h2: Float, h3: Float): Double {
        val d12 = hueDist(h1, h2).toDouble()
        val d23 = hueDist(h2, h3).toDouble()
        val d13 = hueDist(h1, h3).toDouble()
        val dists = listOf(d12, d23, d13).sorted()

        // Penalise near-monochromatic triplets strongly.
        if (dists[2] < 25.0) return 0.1

        // Reward triadic: each pair ideally ~120° apart.
        val triadicScore = dists.sumOf { d ->
            (1.0 - abs(d - 120.0) / 90.0).coerceIn(0.0, 1.0)
        } / 3.0

        // Reward complementary: at least one pair ideally ~180° apart.
        val complementaryScore = dists.maxOf { d ->
            (1.0 - abs(d - 180.0) / 70.0).coerceIn(0.0, 1.0)
        }

        // Reward hue spread: wider is more diverse.
        val spread = (dists[2] / 180.0).coerceIn(0.0, 1.0)

        return (triadicScore * 0.4 + complementaryScore * 0.3 + spread * 0.3)
            .coerceIn(0.0, 1.0)
    }    

    /**
     * Returns true if [rgb1] and [rgb2] are perceptually close, using the
     * OKLab color space for a uniform perceptual distance metric.
     *
     * OKLab is lightweight (two 3×3 matrix multiplications + cube-root) and
     * self-contained — no extra dependencies needed.  It is far more reliable
     * than RGB Euclidean distance for hue-similar-but-brightness-different
     * pairs (e.g. dark purple vs bright purple) that mislead RGB matching.
     *
     * Threshold 0.15 ≈ a "clearly similar" perceptual step in OKLab's
     * normalised [0, 1] lightness range.
     */
    private fun colorSimilar(rgb1: Int, rgb2: Int, threshold: Float = 0.15f): Boolean {
        return perceptualDistance(rgb1, rgb2) < threshold
    }

    private fun perceptualDistance(rgb1: Int, rgb2: Int): Float {
        val (l1, a1, b1) = rgbToOklab(rgb1)
        val (l2, a2, b2) = rgbToOklab(rgb2)
        val dSq = (l1 - l2) * (l1 - l2) +
            (a1 - a2) * (a1 - a2) +
            (b1 - b2) * (b1 - b2)
        return sqrt(dSq)
    }

    /**
     * Converts an ARGB integer to OKLab (L, a, b).
     *
     * Pipeline: sRGB → linear RGB (gamma expand) → LMS (via M1) → LMS^(1/3) → Lab (via M2).
     * Coefficients from https://bottosson.github.io/posts/oklab/
     */
    private fun rgbToOklab(rgb: Int): Triple<Float, Float, Float> {
        // sRGB channels in [0, 1]
        val r = srgbToLinear(((rgb shr 16) and 0xFF) / 255f)
        val g = srgbToLinear(((rgb shr 8) and 0xFF) / 255f)
        val b = srgbToLinear((rgb and 0xFF) / 255f)

        // M1: linear sRGB → LMS
        val l = 0.4122214708f * r + 0.5363325363f * g + 0.0514459929f * b
        val m = 0.2119034982f * r + 0.6806995451f * g + 0.1073969566f * b
        val s = 0.0883024619f * r + 0.2817188376f * g + 0.6299787005f * b

        // Cube root
        val lc = cbrt(l); val mc = cbrt(m); val sc = cbrt(s)

        // M2: LMS^(1/3) → OKLab
        return Triple(
            0.2104542553f * lc + 0.7936177850f * mc - 0.0040720468f * sc,
            1.9779984951f * lc - 2.4285922050f * mc + 0.4505937099f * sc,
            0.0259040371f * lc + 0.7827717662f * mc - 0.8086757660f * sc,
        )
    }

    /** Expands sRGB gamma ([0,1] → linear). */
    private fun srgbToLinear(c: Float): Float =
        if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)

    /** Cube root that handles negative values correctly. */
    private fun cbrt(x: Float): Float =
        if (x >= 0f) x.pow(1f / 3f) else -(-x).pow(1f / 3f)

    // ── Derived highlight / shadow ────────────────────────────────────────────

    /** Lightens [baseRgb] to produce a highlight tone (L → 0.75, S softened). */
    private fun deriveHighlight(baseRgb: Int): Int {
        val hsl = rgbToHsl(baseRgb)
        hsl[2] = 0.75f
        hsl[1] = (hsl[1] * 0.70f).coerceAtLeast(0.15f)
        return hslToRgb(hsl[0], hsl[1], hsl[2])
    }

    /** Produces a related mid-tone support colour for a one/two-family palette. */
    private fun deriveSecondary(baseRgb: Int): Int {
        val hsl = rgbToHsl(baseRgb)
        hsl[2] = (hsl[2] + 0.18f).coerceIn(0.28f, 0.44f)
        hsl[1] = (hsl[1] * 0.90f).coerceAtLeast(0.20f)
        return hslToRgb(hsl[0], hsl[1], hsl[2])
    }

    /** Produces a stronger same-family accent only when no second family exists. */
    private fun deriveAccent(baseRgb: Int): Int {
        val hsl = rgbToHsl(baseRgb)
        hsl[2] = (hsl[2] + 0.28f).coerceIn(0.42f, 0.62f)
        hsl[1] = (hsl[1] * 1.12f).coerceIn(0.28f, 0.90f)
        return hslToRgb(hsl[0], hsl[1], hsl[2])
    }

    /** Darkens [baseRgb] to produce a shadow tone (L → 0.18, S softened). */
    private fun deriveShadow(baseRgb: Int): Int {
        val hsl = rgbToHsl(baseRgb)
        hsl[2] = 0.18f
        hsl[1] = (hsl[1] * 0.80f).coerceAtLeast(0.10f)
        return hslToRgb(hsl[0], hsl[1], hsl[2])
    }

    // ── Fallback helpers ─────────────────────────────────────────────────────

    /**
     * Best-effort 5-colour list from Palette's own named swatch hierarchy.
     * Used when the scoring pass finds too few candidates.
     */
    private fun buildFallbackFromPalette(palette: Palette): List<Int> {
        val swatches = listOfNotNull(
            palette.vibrantSwatch,
            palette.darkVibrantSwatch,
            palette.lightVibrantSwatch,
            palette.mutedSwatch,
            palette.darkMutedSwatch,
            palette.lightMutedSwatch,
            palette.dominantSwatch,
        ).distinctBy { it.rgb }

        val colors = swatches.map { it.rgb }.toMutableList()
        while (colors.size < 5) colors.add(FALLBACK[colors.size])
        return colors.take(5)
    }

    // ── HSL ↔ RGB conversion helpers ─────────────────────────────────────────

    /** Converts an ARGB [rgb] integer to HSL (h: 0..360, s: 0..1, l: 0..1). */
    private fun rgbToHsl(rgb: Int): FloatArray {
        val r = ((rgb shr 16) and 0xFF) / 255f
        val g = ((rgb shr 8) and 0xFF) / 255f
        val b = (rgb and 0xFF) / 255f
        val max = maxOf(r, g, b); val min = minOf(r, g, b)
        val l = (max + min) / 2f
        if (max == min) return floatArrayOf(0f, 0f, l)
        val d = max - min
        val s = if (l > 0.5f) d / (2f - max - min) else d / (max + min)
        val h = when (max) {
            r    -> ((g - b) / d + (if (g < b) 6f else 0f)) * 60f
            g    -> ((b - r) / d + 2f) * 60f
            else -> ((r - g) / d + 4f) * 60f
        }
        return floatArrayOf(h, s, l)
    }

    /** Converts HSL (h: 0..360, s: 0..1, l: 0..1) to an opaque ARGB integer. */
    private fun hslToRgb(h: Float, s: Float, l: Float): Int {
        if (s == 0f) {
            val v = (l * 255).toInt().coerceIn(0, 255)
            return android.graphics.Color.rgb(v, v, v)
        }
        val q = if (l < 0.5f) l * (1 + s) else l + s - l * s
        val p = 2 * l - q
        val hNorm = h / 360f
        fun hue2rgb(t: Float): Float {
            val tt = when {
                t < 0 -> t + 1f
                t > 1 -> t - 1f
                else  -> t
            }
            return when {
                tt < 1f / 6 -> p + (q - p) * 6 * tt
                tt < 1f / 2 -> q
                tt < 2f / 3 -> p + (q - p) * (2f / 3 - tt) * 6
                else        -> p
            }
        }
        return android.graphics.Color.rgb(
            (hue2rgb(hNorm + 1f / 3) * 255).toInt().coerceIn(0, 255),
            (hue2rgb(hNorm) * 255).toInt().coerceIn(0, 255),
            (hue2rgb(hNorm - 1f / 3) * 255).toInt().coerceIn(0, 255),
        )
    }

    // ── Geometry helpers ─────────────────────────────────────────────────────

    /** Shortest angular distance between two HSL hues (0..360). */
    private fun hueDist(h1: Float, h2: Float): Float {
        val d = abs(h1 - h2)
        return if (d > 180f) 360f - d else d
    }
}
