package dev.wndavenz.music

import kotlin.math.pow
import kotlin.math.sqrt

// ── Pure color-science helpers (dipindah dari NativePaletteBridge.kt) ─────────
// Semua fungsi di file ini stateless — tidak menyentuh state instance.

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
internal fun colorSimilar(rgb1: Int, rgb2: Int, threshold: Float = 0.15f): Boolean {
    return perceptualDistance(rgb1, rgb2) < threshold
}

internal fun perceptualDistance(rgb1: Int, rgb2: Int): Float {
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
internal fun rgbToOklab(rgb: Int): Triple<Float, Float, Float> {
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
internal fun srgbToLinear(c: Float): Float =
    if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)

/** Cube root that handles negative values correctly. */
internal fun cbrt(x: Float): Float =
    if (x >= 0f) x.pow(1f / 3f) else -(-x).pow(1f / 3f)
