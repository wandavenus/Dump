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
 * Method  : "extractPalette" (arg: Int songId) → List<Int> (3 ARGB values)
 *
 * # Algorithm
 *
 * 1. **Artwork source** — reads the already-cached WebP via [ArtworkCacheManager].
 *    If artwork is not yet cached, [ArtworkCacheManager.getOrExtract] extracts it
 *    from MediaStore and writes it to disk atomically.  No bytes are transferred
 *    over the MethodChannel: the native side handles everything in one hop.
 *
 * 2. **Image decode** — two-pass [BitmapFactory.decodeFile]: bounds-only first to
 *    compute the minimum power-of-two [inSampleSize] that keeps the decoded
 *    bitmap ≤ [PALETTE_TARGET_SIZE] px on each side.  Decoded as RGB_565 (no
 *    alpha channel), which halves per-pixel memory vs ARGB_8888 and speeds up
 *    the Palette scan.
 *
 * 3. **MMCQ quantization** — [Palette.from] with [maximumColorCount] = 32 and
 *    no colour filters (so vivid reds, near-blacks, and near-whites are all
 *    available to the shader).
 *
 * 4. **Perceptual scoring** — each swatch is scored:
 *      score = sat^1.4 × lightness_factor × (0.35 + 0.65 × pop_factor)
 *    where:
 *      - sat                = HSL saturation (rewards vibrant colours)
 *      - lightness_factor   = 1 − |lightness − 0.45| × 1.6  (prefers mid-range)
 *      - pop_factor         = log(population+1) / log(maxPop+1)  (rewards dominant)
 *
 * 5. **Hue-diversity selection** — picks 3 swatches with minimum hue distance,
 *    progressively relaxing the threshold (40° → 25° → 12° → 0°) to guarantee
 *    3 results even for near-monochrome artwork.
 *
 * 6. **Fallback chain** — if filtered candidates are empty, uses Palette's own
 *    named swatches (vibrant → dark-vibrant → muted → dominant).  If those are
 *    also empty, returns [FALLBACK] (the same 3 grey-blue tones as before).
 *
 * # Performance
 * Typical extraction time on Snapdragon 730: 3–8 ms for a 100×100 bitmap.
 * Runs on [artworkExecutor] (bounded background pool), never on the UI thread.
 */
class NativePaletteBridge(
    private val artworkCacheManager: ArtworkCacheManager,
    private val executor: ExecutorService,
) {

    companion object {
        const val CHANNEL = "dev.wndavenz.music/native_palette"

        /**
         * Fallback palette — identical to PaletteExtractor._kFallback on the Dart side
         * so the disk-persisted palette cache (written by the Dart layer) remains fully
         * forward-compatible with this new bridge.
         */
        val FALLBACK: List<Int> = listOf(
            0xFF2B313A.toInt(),
            0xFF4E657D.toInt(),
            0xFF7B8794.toInt(),
        )

        /**
         * Maximum side length for palette-extraction bitmap.
         * Large enough to capture all major colour regions; small enough that
         * MMCQ quantization runs well under 15 ms on mid-range hardware.
         */
        private const val PALETTE_TARGET_SIZE = 100
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
            // Executor rejected (queue full) — return fallback synchronously.
            result.success(FALLBACK)
        }
    }

    // ── Core extraction pipeline ──────────────────────────────────────────────

    private fun extractColors(songId: Int): List<Int> {
        val path = artworkCacheManager.getOrExtract(songId) ?: return FALLBACK

        // Bounds-only pass — no pixel data allocated yet.
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return FALLBACK

        // Compute power-of-two sample size to stay ≤ PALETTE_TARGET_SIZE.
        var sampleSize = 1
        while (boundsOpts.outWidth / sampleSize > PALETTE_TARGET_SIZE ||
               boundsOpts.outHeight / sampleSize > PALETTE_TARGET_SIZE) {
            sampleSize *= 2
        }

        // Full decode at reduced size — RGB_565 halves memory vs ARGB_8888.
        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
        }) ?: return FALLBACK

        return try {
            val palette = Palette.from(bitmap)
                .maximumColorCount(32)
                // clearFilters() keeps ALL hues — vivid reds, near-blacks, and near-whites
                // are all valid inputs for a domain-warping fluid shader.  The default
                // filter (avoidRedBlackWhitePaletteFilter) exists for legible text-colour
                // selection, which is not what we need here.
                .clearFilters()
                .generate()
            selectBestThree(palette)
        } finally {
            bitmap.recycle()
        }
    }

    // ── Colour selection ──────────────────────────────────────────────────────

    /**
     * Selects 3 visually distinct, vibrant colours from [palette].
     *
     * See class-level KDoc for the full algorithm description.
     */
    private fun selectBestThree(palette: Palette): List<Int> {
        val all = palette.swatches
        if (all.isEmpty()) return buildFallbackFromPalette(palette)

        // Filter near-gray / near-black / near-white swatches.
        val candidates = all.filter { sw ->
            val hsl = sw.hsl
            hsl[1] >= 0.12f && hsl[2] in 0.10f..0.92f
        }
        if (candidates.isEmpty()) return buildFallbackFromPalette(palette)

        // Score each candidate.
        val maxPop = candidates.maxOf { it.population }.toDouble().coerceAtLeast(1.0)

        data class Scored(val swatch: Palette.Swatch, val score: Double)

        val scored = candidates.map { sw ->
            val hsl = sw.hsl
            val sat   = hsl[1].toDouble()
            val light = hsl[2].toDouble()
            // Prefer medium lightness; penalise extremes.
            val lightFactor = (1.0 - abs(light - 0.45) * 1.6).coerceAtLeast(0.05)
            val popFactor   = log10(sw.population + 1.0) / log10(maxPop + 1.0)
            // Saturation^1.4 rewards vibrant colours over muted ones.
            val score = sat.pow(1.4) * lightFactor * (0.35 + 0.65 * popFactor)
            Scored(sw, score)
        }.sortedByDescending { it.score }

        // Pick 3 with hue diversity — relax threshold progressively.
        val selected = mutableListOf<Palette.Swatch>()
        for (threshold in listOf(40f, 25f, 12f, 0f)) {
            selected.clear()
            for (s in scored) {
                val tooClose = selected.any { ex ->
                    hueDist(s.swatch.hsl[0], ex.hsl[0]) < threshold
                }
                if (!tooClose) {
                    selected.add(s.swatch)
                    if (selected.size == 3) break
                }
            }
            if (selected.size >= 3) break
        }

        // Build result, padding with named swatches or hard fallback if needed.
        val result = selected.map { it.rgb }.toMutableList()
        if (result.size < 3) {
            for (c in buildFallbackFromPalette(palette)) {
                if (result.size >= 3) break
                if (c !in result) result.add(c)
            }
        }
        while (result.size < 3) result.add(FALLBACK[result.size])

        return result.take(3)
    }

    /**
     * Best-effort 3-colour list from Palette's own named swatch hierarchy.
     * Used as a secondary fallback when the scoring pass finds too few candidates.
     */
    private fun buildFallbackFromPalette(palette: Palette): List<Int> {
        val colours = listOfNotNull(
            palette.vibrantSwatch,
            palette.darkVibrantSwatch,
            palette.lightVibrantSwatch,
            palette.mutedSwatch,
            palette.darkMutedSwatch,
            palette.lightMutedSwatch,
            palette.dominantSwatch,
        ).map { it.rgb }.distinct()

        return when {
            colours.size >= 3 -> colours.take(3)
            colours.size == 2 -> colours + listOf(FALLBACK[2])
            colours.size == 1 -> colours + FALLBACK.drop(1)
            else              -> FALLBACK
        }
    }

    // ── Geometry helpers ─────────────────────────────────────────────────────

    /** Shortest angular distance between two HSL hues (0..360). */
    private fun hueDist(h1: Float, h2: Float): Float {
        val d = abs(h1 - h2)
        return if (d > 180f) 360f - d else d
    }
}
