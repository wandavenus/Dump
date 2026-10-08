package dev.wndavenz.music

import androidx.palette.graphics.Palette
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.atomic.AtomicBoolean

// ── Internal data models (dipindah dari NativePaletteBridge.kt) ───────────────

/** A scored swatch — score is the perceptual importance of this color. */
internal data class Scored(val swatch: Palette.Swatch, val score: Double)

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
 *   HSL values for downstream hue and role-assignment calculations.
 */
internal data class ColorCluster(
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

internal class PendingRequest(
    val result: MethodChannel.Result,
) {
    val completed = AtomicBoolean(false)
    var watchdogFuture: ScheduledFuture<*>? = null
}

internal class InFlightJob(
    val songId: Int,
    val requestIds: MutableList<Long> = mutableListOf(),
    var completed: Boolean = false,
    var completion: ((MethodChannel.Result) -> Unit)? = null,
)
