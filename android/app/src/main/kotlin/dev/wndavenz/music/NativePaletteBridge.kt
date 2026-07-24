package dev.wndavenz.music

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.palette.graphics.Palette
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow

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
 *    bitmap ≤ [PALETTE_TARGET_SIZE] px on each side.  Decoded as RGB_565.
 *
 * 3. **MMCQ quantization** — [Palette.from] with [maximumColorCount] = 32 and
 *    no colour filters.
 *
 * 4. **Spatial / subject weighting** — a center-crop (inner 60 % of each axis)
 *    is analysed independently.  Colors prominent in the center receive a ×1.4
 *    score boost, ensuring visually important subjects (characters, objects)
 *    win over large flat backgrounds.
 *
 * 5. **Perceptual scoring** — each swatch is scored:
 *      score = sat^1.4 × lightness_factor × (0.35 + 0.65 × pop_factor) × center_boost
 *    where:
 *      - sat                = HSL saturation
 *      - lightness_factor   = 1 − |lightness − 0.45| × 1.6
 *      - pop_factor         = log(population+1) / log(maxPop+1)
 *      - center_boost       = 1.4 if color is prominent in center crop, else 1.0
 *
 * 6. **Harmony-driven triplet selection** — from the top-12 scored candidates,
 *    all triplet combinations are evaluated.  Each triplet's score is:
 *      triplet_score = sum_of_individual_scores × (1 + 0.5 × harmony_score)
 *    Harmony rewards triadic (≈120° hue spacing), complementary (≈180°), and
 *    wide hue spread; penalises near-monochromatic triplets (spread < 25°).
 *
 * 7. **Role assignment** — the winning triplet is sorted into:
 *      primary   = highest population (main mood)
 *      secondary = second-most-present
 *      accent    = most saturated (vibrant pop)
 *
 * 8. **Highlight + Shadow** — two extra colors from the remaining candidates:
 *      highlight = lightest saturated swatch (L > 0.55, S > 0.10)
 *      shadow    = darkest saturated swatch  (L < 0.45, S > 0.08)
 *    Derived from primary's hue if no suitable candidate exists.
 *
 * 9. **Output** — 5-element List<Int> [primary, secondary, accent, highlight, shadow].
 *    Existing callers that only read index 0/1/2 remain fully compatible.
 *
 * # Performance
 * Center-crop secondary palette adds ≈1–2 ms.  Total ≈4–10 ms on SD730.
 */
class NativePaletteBridge(
    private val artworkCacheManager: ArtworkCacheManager,
    private val executor: ExecutorService,
) {

    companion object {
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

        private const val PALETTE_TARGET_SIZE = 100

        /** Center-crop fraction: inner (1 - 2×margin) of each axis. */
        private const val CENTER_MARGIN = 0.20f

        /** Maximum candidates fed into the harmony triplet search. */
        private const val TOP_N = 12
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Public entry point ────────────────────────────────────────────────────

    fun handleCall(method: String, args: Any?, result: MethodChannel.Result) {
        if (method != "extractPalette") {
            result.notImplemented()
            return
        }
        val songId = (args as? Int) ?: run { result.success(FALLBACK); return }

        try {
            executor.execute {
                val colors = runCatching { extractColors(songId) }.getOrDefault(FALLBACK)
                mainHandler.post { result.success(colors) }
            }
        } catch (_: Exception) {
            result.success(FALLBACK)
        }
    }

    // ── Core extraction pipeline ──────────────────────────────────────────────

    private fun extractColors(songId: Int): List<Int> {
        val path = artworkCacheManager.getOrExtract(songId) ?: return FALLBACK

        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return FALLBACK

        var sampleSize = 1
        while (boundsOpts.outWidth / sampleSize > PALETTE_TARGET_SIZE ||
               boundsOpts.outHeight / sampleSize > PALETTE_TARGET_SIZE) {
            sampleSize *= 2
        }

        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
        }) ?: return FALLBACK

        return try {
            val palette = Palette.from(bitmap)
                .maximumColorCount(32)
                .clearFilters()
                .generate()
            selectBestFive(palette, bitmap)
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
    private fun selectBestFive(palette: Palette, bitmap: Bitmap): List<Int> {
        val all = palette.swatches
        if (all.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 1: Center-crop palette for spatial weighting.
        val centerColors = extractCenterColors(bitmap)

        // Step 2: Filter achromatic swatches.
        val candidates = all.filter { sw ->
            val hsl = sw.hsl
            hsl[1] >= 0.10f && hsl[2] in 0.08f..0.93f
        }
        if (candidates.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 3: Score each candidate.
        val maxPop = candidates.maxOf { it.population }.toDouble().coerceAtLeast(1.0)

        data class Scored(val swatch: Palette.Swatch, val score: Double)

        val scored = candidates.map { sw ->
            val hsl   = sw.hsl
            val sat   = hsl[1].toDouble()
            val light = hsl[2].toDouble()
            val lightFactor = (1.0 - abs(light - 0.45) * 1.6).coerceAtLeast(0.05)
            val popFactor   = log10(sw.population + 1.0) / log10(maxPop + 1.0)
            // Center boost: subjects prominent near the image center score higher.
            val centerBoost = if (centerColors.any { colorSimilar(it, sw.rgb) }) 1.4 else 1.0
            val score = sat.pow(1.4) * lightFactor * (0.35 + 0.65 * popFactor) * centerBoost
            Scored(sw, score)
        }.sortedByDescending { it.score }

        // Step 4: Harmony-driven triplet selection from top-N candidates.
        val top = scored.take(TOP_N)
        val bestTriplet = selectHarmoniousTriplet(
            top.map { it.swatch },
            top.map { it.score }
        )

        if (bestTriplet.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 5: Assign roles within the triplet.
        //   accent    = most saturated (vibrant pop)
        //   primary   = highest population (main mood)
        //   secondary = remainder
        val sortedBySat = bestTriplet.sortedByDescending { it.hsl[1] }
        val accent = sortedBySat[0]
        val primarySecondary = sortedBySat.drop(1).sortedByDescending { it.population }
        val primary   = primarySecondary.getOrNull(0) ?: bestTriplet[0]
        val secondary = primarySecondary.getOrNull(1) ?: bestTriplet[1]

        // Step 6: Highlight + Shadow from remaining candidates.
        val usedRgbs = setOf(primary.rgb, secondary.rgb, accent.rgb)
        val rest     = candidates.filter { it.rgb !in usedRgbs }

        val highlightSwatch = rest.filter { sw ->
            val hsl = sw.hsl; hsl[2] > 0.55f && hsl[1] > 0.10f
        }.maxByOrNull { it.hsl[2] }
        val highlightColor = highlightSwatch?.rgb ?: deriveHighlight(primary.rgb)

        val shadowSwatch = rest.filter { sw ->
            sw.rgb != highlightSwatch?.rgb
            val hsl = sw.hsl; hsl[2] < 0.45f && hsl[1] > 0.08f
        }.minByOrNull { it.hsl[2] }
        val shadowColor = shadowSwatch?.rgb ?: deriveShadow(primary.rgb)

        return listOf(primary.rgb, secondary.rgb, accent.rgb, highlightColor, shadowColor)
    }

    // ── Harmony triplet evaluation ────────────────────────────────────────────

    /**
     * From [swatches] (pre-sorted by individual score), evaluates all
     * combinations of 3 and returns the triplet that maximises:
     *   sum_of_individual_scores × (1 + 0.5 × harmony_score)
     *
     * At most [TOP_N] swatches → at most C(12,3)=220 combinations: negligible.
     */
    private fun selectHarmoniousTriplet(
        swatches: List<Palette.Swatch>,
        scores: List<Double>,
    ): List<Palette.Swatch> {
        val n = swatches.size
        if (n < 3) return swatches

        var bestCombo  = emptyList<Palette.Swatch>()
        var bestScore  = -1.0

        for (i in 0 until n) {
            for (j in i + 1 until n) {
                for (k in j + 1 until n) {
                    val indivSum = scores[i] + scores[j] + scores[k]
                    val harmony  = harmonyScore(
                        swatches[i].hsl[0],
                        swatches[j].hsl[0],
                        swatches[k].hsl[0],
                    )
                    val total = indivSum * (1.0 + 0.5 * harmony)
                    if (total > bestScore) {
                        bestScore = total
                        bestCombo = listOf(swatches[i], swatches[j], swatches[k])
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

    // ── Spatial / center weighting ────────────────────────────────────────────

    /**
     * Extracts the dominant colors from the center crop of [bitmap]
     * (inner 60 % of each axis).  Used to boost scores of swatches that
     * appear prominently near the visual subject.
     */
    private fun extractCenterColors(bitmap: Bitmap): List<Int> {
        val w = bitmap.width; val h = bitmap.height
        val cx = (w * CENTER_MARGIN).toInt()
        val cy = (h * CENTER_MARGIN).toInt()
        val cw = (w * (1f - 2 * CENTER_MARGIN)).toInt().coerceAtLeast(1)
        val ch = (h * (1f - 2 * CENTER_MARGIN)).toInt().coerceAtLeast(1)
        return try {
            val center = Bitmap.createBitmap(bitmap, cx, cy, cw, ch)
            val p = Palette.from(center).maximumColorCount(8).clearFilters().generate()
            center.recycle()
            p.swatches.sortedByDescending { it.population }.take(4).map { it.rgb }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * Returns true if [rgb1] and [rgb2] are perceptually close
     * (Euclidean RGB distance < 80, ≈ one "step" in a 3-band gradient).
     */
    private fun colorSimilar(rgb1: Int, rgb2: Int): Boolean {
        val r1 = (rgb1 shr 16) and 0xFF; val r2 = (rgb2 shr 16) and 0xFF
        val g1 = (rgb1 shr 8) and 0xFF;  val g2 = (rgb2 shr 8) and 0xFF
        val b1 = rgb1 and 0xFF;           val b2 = rgb2 and 0xFF
        val dSq = (r1 - r2).let { it * it } +
                  (g1 - g2).let { it * it } +
                  (b1 - b2).let { it * it }
        return dSq < 80 * 80
    }

    // ── Derived highlight / shadow ────────────────────────────────────────────

    /** Lightens [baseRgb] to produce a highlight tone (L → 0.75, S softened). */
    private fun deriveHighlight(baseRgb: Int): Int {
        val hsl = rgbToHsl(baseRgb)
        hsl[2] = 0.75f
        hsl[1] = (hsl[1] * 0.70f).coerceAtLeast(0.15f)
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
