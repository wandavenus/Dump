package dev.wndavenz.music

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

/**
 * Shared bitmap decode/normalize helpers used by both FallbackBitmapLoader and
 * PlaybackNotificationManager. Consolidates what used to be copy-pasted
 * implementations in each class so a fix in one place applies to both — no
 * more drifting duplicates (e.g. one copy using `shl 1` and another `*= 2`
 * for the same power-of-two downscale).
 */
internal object BitmapUtils {

    /** Smallest power-of-two sample size so neither dimension exceeds [maxPx]. */
    fun computeSampleSize(w: Int, h: Int, maxPx: Int): Int {
        var s = 1
        while ((w / s) > maxPx || (h / s) > maxPx) s *= 2
        return s
    }

    /**
     * Two-pass decode capped at [maxPx] on the longest side — bounds pass first
     * (zero pixel allocation), then a sampled ARGB_8888 decode. Returns null if
     * the bytes are not a decodable image or the dimensions are invalid.
     */
    fun decodeCapped(bytes: ByteArray, maxPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val sample = computeSampleSize(bounds.outWidth, bounds.outHeight, maxPx)
        return BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                // ARGB_8888 so already-square art hits the fast path in
                // normalizeSquare() instead of being re-letterboxed.
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        )
    }

    /**
     * Letterboxes [source] onto a square with a black background, capped at
     * [maxPx]×[maxPx]. SystemUI / MIUI media templates fill the artwork area by
     * center-cropping non-square bitmaps — pre-letterboxing keeps the full image
     * visible instead of zoomed.
     *
     * Never upscales: the canvas is no larger than the source's longest side
     * (capped at [maxPx]), so small art stays at native resolution and the
     * system does the final scaling instead of us adding an upscale pass.
     */
    fun normalizeSquare(source: Bitmap, maxPx: Int): Bitmap {
        if (source.width <= 0 || source.height <= 0) return source
        val target = minOf(maxPx, maxOf(source.width, source.height))
        if (source.width == target && source.height == target) return source

        val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.BLACK)

        val scale = minOf(
            target.toFloat() / source.width.toFloat(),
            target.toFloat() / source.height.toFloat(),
        )
        val drawnW = source.width * scale
        val drawnH = source.height * scale
        val left = (target - drawnW) / 2f
        val top = (target - drawnH) / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        canvas.drawBitmap(source, null, RectF(left, top, left + drawnW, top + drawnH), paint)
        return out
    }
}
