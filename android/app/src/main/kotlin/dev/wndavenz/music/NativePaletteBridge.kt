package dev.wndavenz.music

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.palette.graphics.Palette
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
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
 *    soft artwork gradients do not acquire avoidable 16-bit color banding.
 *
 * 3. **MMCQ quantization** — [Palette.from] with [maximumColorCount] = 96 and
 *    no colour filters. The result is a bounded list of AndroidX Palette
 *    swatches for the selection pass.
 *
 * 4. **Perceptual scoring** — each chromatic swatch is scored:
 *      score = (0.90 × pop_factor + 0.10 × sat^0.8)
 *              × lightness_factor × dark_bonus
 *    where:
 *      - pop_factor         = log(population+1) / log(maxPop+1)
 *      - sat                = HSL saturation
 *      - lightness_factor   = max(0.05, 1 − |lightness − 0.50| × 0.9)
 *      - dark_bonus         = 1.20 when lightness < 0.25, otherwise 1.0
 *
 * 5. **OKLab color clustering** — perceptually similar swatches are merged into
 *    [ColorCluster] groups using the existing OKLab [colorSimilar] function
 *    (threshold 0.15).  This corrects a fundamental weakness of MMCQ: a single
 *    visual color family (e.g. Black + Navy + Dark Blue) is often split into
 *    multiple Palette swatches, each covering a small fraction of the image.
 *    Without clustering, a 28 % skin tone wins over a 48 % dark family simply
 *    because the dark pixels are fragmented across three separate buckets.
 *    After clustering, the merged dark family competes with its full weight.
 *
 * 6. **Coverage-driven role selection** — roles are selected greedily from the
 *    highest-scoring clusters. Population remains the main signal, while
 *    perceptual distance from already-selected roles prevents three shades of
 *    the same blue from consuming the palette. This preserves real secondary
 *    families such as skin, beige, green, or red instead of inventing a
 *    mathematically related substitute.
 *    Only the top [TOP_N] (32) clusters are considered for role selection.
 *
 * 7. **Role assignment**:
 *      primary   = largest visual family
 *      secondary = largest remaining sufficiently different family
 *      accent    = most useful remaining coverage/diversity family
 *
 * 8. **Neutral-dominance correction** — after chromatic selection, the most
 *    populated near-neutral swatch (HSL saturation < 0.12) can replace primary
 *    when its population exceeds twice the selected chromatic family's merged
 *    population. This preserves genuinely dominant white, gray, or black
 *    artwork backgrounds.
 *
 * 9. **Highlight + Shadow** — two extra colors from the remaining clusters:
 *      highlight = lightest saturated representative (L > 0.55, S > 0.10)
 *      shadow    = darkest saturated representative  (L < 0.45, S > 0.08)
 *    Candidates must remain within [HUE_ANCHOR_THRESHOLD] degrees of the
 *    primary hue. For neutral primaries, both colors are derived from primary.
 *    If no suitable cluster exists, the corresponding color is derived from
 *    primary.
 *
 * 10. **Output** — 5-element List<Int> [primary, secondary, accent, highlight, shadow].
 *     Existing callers that only read indices 0/1/2 remain compatible. If the
 *     artwork has fewer than three meaningful families, missing supporting roles
 *     are derived from primary rather than replacing valid families with named
 *     swatches.
 *
 * # Performance
 * The palette pass is intentionally bounded to a bitmap whose decoded width and
 * height are each at most [PALETTE_TARGET_SIZE] pixels. Clustering is a greedy
 * O(n²) sweep over the scored swatches (at most 96 from AndroidX Palette), and
 * role selection is linear over the resulting clusters after the top-32 cap.
 * No extra bitmap decoding or Palette generation is required.
 * Timings depend on whether artwork is already cached: cache hits avoid
 * MediaStore extraction, while cache misses include artwork extraction and
 * WebP encoding in [ArtworkCacheManager].
 *
 * Concurrent requests for the same song ID share one native extraction job.
 * Queue rejection and sampled extraction/coalescing metrics are tracked without
 * increasing the bounded artwork executor size.
 */
class NativePaletteBridge(
    private val artworkCacheManager: ArtworkCacheManager,
    private val executor: ExecutorService,
    mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val callbackWatchdog: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "NativePaletteCallbackWatchdog").apply { isDaemon = true }
    },
    private val extractColorsOverride: ((Int) -> List<Int>?)? = null,
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

        private const val PALETTE_TARGET_SIZE = 256

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

        /** Bounds the time a queued callback may keep a Dart Future pending. */
        private const val CALLBACK_WATCHDOG_DELAY_MS = 5_000L
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
     *   HSL values for downstream hue and role-assignment calculations.
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

    private class PendingRequest(
        val result: MethodChannel.Result,
    ) {
        val completed = AtomicBoolean(false)
        var watchdogFuture: ScheduledFuture<*>? = null
    }

    private val mainHandler = mainHandler

    private class InFlightJob(
        val songId: Int,
        val requestIds: MutableList<Long> = mutableListOf(),
        var completed: Boolean = false,
        var completion: ((MethodChannel.Result) -> Unit)? = null,
    )

    private val requestIds = AtomicLong(0L)
    private val lifecycleLock = Any()
    private val pendingRequests = mutableMapOf<Long, PendingRequest>()
    private val inFlightBySongId = mutableMapOf<Int, InFlightJob>()
    private val extractionCount = AtomicLong(0L)
    private val extractionFailureCount = AtomicLong(0L)
    private val coalescedRequestCount = AtomicLong(0L)
    private val queueRejectedCount = AtomicLong(0L)
    private val totalExtractionDurationMs = AtomicLong(0L)
    private val maxQueueDepth = AtomicLong(0L)

    @Volatile
    private var disposed = false

    // ── Public entry point ────────────────────────────────────────────────────

    fun handleCall(method: String, args: Any?, result: MethodChannel.Result) {
        if (method == "getCacheVersion") {
            result.success(CACHE_VERSION)
            return
        }
        if (method != "extractPalette") {
            result.notImplemented()
            return
        }
        val songId = (args as? Int)
        if (songId == null || songId <= 0) {
            result.error("invalid_song_id", "extractPalette requires a positive Int songId", null)
            return
        }

        val requestId = requestIds.incrementAndGet()
        val request = PendingRequest(result)
        var jobToSubmit: InFlightJob? = null
        var completedJob: InFlightJob? = null
        synchronized(lifecycleLock) {
            if (disposed) {
                result.error("palette_unavailable", "Palette bridge is shutting down", null)
                return
            }
            pendingRequests[requestId] = request
            val existingJob = inFlightBySongId[songId]
            if (existingJob != null) {
                existingJob.requestIds += requestId
                coalescedRequestCount.incrementAndGet()
                if (existingJob.completed) {
                    completedJob = existingJob
                }
            } else {
                jobToSubmit = InFlightJob(songId).also {
                    it.requestIds += requestId
                    inFlightBySongId[songId] = it
                }
            }
        }

        completedJob?.let { job ->
            val completion = job.completion
            if (completion != null) {
                completeOnMain(job, requestId, request, completion)
            }
            return
        }

        val job = jobToSubmit ?: return
        try {
            executor.execute {
                if (!isJobActive(job)) return@execute
                val startedAt = SystemClock.elapsedRealtime()
                var outcome = "success"
                try {
                    val colors = extractColorsOverride?.invoke(job.songId)
                        ?: extractColors(job.songId)
                    completeJobOnMain(job) {
                        it.success(colors)
                    }
                } catch (error: OutOfMemoryError) {
                    outcome = "oom"
                    Log.e(
                        TAG,
                        "Palette extraction ran out of memory for songId=${job.songId}",
                        error,
                    )
                    completeJobOnMain(job) {
                        it.error(
                            "palette_memory_error",
                            "Not enough memory to extract palette",
                            null,
                        )
                    }
                } catch (error: Exception) {
                    outcome = "error"
                    Log.w(TAG, "Palette extraction failed for songId=${job.songId}", error)
                    completeJobOnMain(job) {
                        it.error(
                            "palette_extraction_failed",
                            error.message ?: "Palette extraction failed",
                            null,
                        )
                    }
                } finally {
                    recordExtractionMetrics(
                        job.songId,
                        SystemClock.elapsedRealtime() - startedAt,
                        outcome,
                    )
                }
            }
            recordQueueDepth()
        } catch (error: RejectedExecutionException) {
            val rejected = queueRejectedCount.incrementAndGet()
            Log.w(TAG, "Palette queue rejected songId=${job.songId} count=$rejected", error)
            completeJobOnMain(job) {
                it.error("palette_busy", "Palette extraction queue is busy", null)
            }
            recordQueueDepth()
        }
    }

    /**
     * Completes all requests and prevents work/callbacks from replying after
     * the Flutter engine is being torn down.
     *
     * Must be called before the executor supplied to this bridge is shut down.
     */
    fun dispose() {
        val requests = synchronized(lifecycleLock) {
            if (disposed) return
            disposed = true
            val snapshot = pendingRequests.values.toList()
            pendingRequests.clear()
            inFlightBySongId.clear()
            snapshot
        }
        callbackWatchdog.shutdownNow()

        requests.forEach { request ->
            if (request.completed.compareAndSet(false, true)) {
                try {
                    request.result.error(
                        "palette_unavailable",
                        "Palette bridge is shutting down",
                        null,
                    )
                } catch (error: Exception) {
                    Log.w(TAG, "Failed to complete palette request during dispose", error)
                }
            }
        }
    }

    private fun isJobActive(job: InFlightJob): Boolean =
        synchronized(lifecycleLock) {
            !disposed &&
                inFlightBySongId[job.songId] === job &&
                !job.completed &&
                job.requestIds.any { pendingRequests.containsKey(it) }
        }

    private fun recordQueueDepth() {
        val queueDepth = (executor as? ThreadPoolExecutor)?.queue?.size?.toLong() ?: return
        maxQueueDepth.updateAndGet { maxOf(it, queueDepth) }
    }

    private fun recordExtractionMetrics(songId: Int, durationMs: Long, outcome: String) {
        val completed = extractionCount.incrementAndGet()
        val totalDuration = totalExtractionDurationMs.addAndGet(durationMs)
        if (outcome != "success") {
            extractionFailureCount.incrementAndGet()
        }
        recordQueueDepth()
        if (Log.isLoggable(TAG, Log.DEBUG) && (completed == 1L || completed % 32L == 0L)) {
            val coalesced = coalescedRequestCount.get()
            val rejected = queueRejectedCount.get()
            val averageMs = totalDuration / completed.coerceAtLeast(1L)
            val queueDepth = (executor as? ThreadPoolExecutor)?.queue?.size ?: -1
            Log.d(
                TAG,
                "metrics extractions=$completed coalesced=$coalesced " +
                    "failures=${extractionFailureCount.get()} queueRejected=$rejected " +
                    "avgMs=$averageMs outcome=$outcome queueDepth=$queueDepth " +
                    "maxQueueDepth=${maxQueueDepth.get()} lastSongId=$songId",
            )
        }
    }

    private fun completeJobOnMain(
        job: InFlightJob,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        val requests = synchronized(lifecycleLock) {
            if (disposed || inFlightBySongId[job.songId] !== job) {
                return
            }
            job.completed = true
            job.completion = completion
            job.requestIds.mapNotNull { id ->
                pendingRequests[id]?.let { id to it }
            }
        }
        requests.forEach { (requestId, request) ->
            completeOnMain(job, requestId, request, completion)
        }
    }

    /**
     * Posts a result to the main thread and guards it with an atomic
     * exactly-once check. A watchdog handles the rare case where the Handler
     * accepts the runnable but its Looper stops dispatching during teardown.
     */
    private fun completeOnMain(
        job: InFlightJob,
        requestId: Long,
        request: PendingRequest,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        val deliver = Runnable {
            deliverRequest(job, requestId, request, completion, null)
        }

        if (!mainHandler.post(deliver)) {
            deliverRequest(
                job = job,
                requestId = requestId,
                request = request,
                completion = {
                    it.error(
                        "palette_unavailable",
                        "Palette result channel is unavailable",
                        null,
                    )
                },
                fallbackMessage = "Handler rejected palette callback",
            )
            return
        }

        val watchdog = try {
            callbackWatchdog.schedule(
                {
                    deliverRequest(
                        job = job,
                        requestId = requestId,
                        request = request,
                        completion = {
                            it.error(
                                "palette_unavailable",
                                "Palette result channel is unavailable",
                                null,
                            )
                        },
                        fallbackMessage = "Palette callback watchdog fired",
                    )
                },
                CALLBACK_WATCHDOG_DELAY_MS,
                TimeUnit.MILLISECONDS,
            )
        } catch (error: RejectedExecutionException) {
            // dispose() may shut down the watchdog between post() and schedule().
            // The normal Handler callback remains responsible for completion.
            Log.d(TAG, "Palette callback watchdog unavailable", error)
            null
        }

        if (watchdog != null) {
            synchronized(lifecycleLock) {
                if (request.completed.get()) {
                    watchdog.cancel(false)
                } else {
                    request.watchdogFuture = watchdog
                }
            }
        }
    }

    private fun deliverRequest(
        job: InFlightJob,
        requestId: Long,
        request: PendingRequest,
        completion: (MethodChannel.Result) -> Unit,
        fallbackMessage: String?,
    ) {
        synchronized(lifecycleLock) {
            if (pendingRequests[requestId] !== request ||
                !request.completed.compareAndSet(false, true)
            ) {
                return
            }
            request.watchdogFuture?.cancel(false)
            request.watchdogFuture = null
            pendingRequests.remove(requestId)
        }
        try {
            completion(request.result)
        } catch (error: Exception) {
            Log.w(TAG, fallbackMessage ?: "Failed to deliver palette result", error)
        } finally {
            synchronized(lifecycleLock) {
                if (job.completed &&
                    job.requestIds.none { pendingRequests.containsKey(it) }
                ) {
                    inFlightBySongId.remove(job.songId)
                }
            }
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
     * Selects five perceptually useful colors from [palette].
     *
     * Chromatic swatches are filtered, scored primarily by population, merged
     * by OKLab similarity, and selected with coverage/diversity weighting.
     * A strongly dominant neutral swatch can replace the chromatic primary.
     * Returns the named-swatch fallback only if no usable chromatic swatches
     * exist or no clusters remain after filtering.
     */
    internal fun selectBestFiveForTest(palette: Palette): List<Int> =
        selectBestFive(palette)

    private fun selectBestFive(palette: Palette): List<Int> {
        val all = palette.swatches
        if (all.isEmpty()) return buildFallbackFromPalette(palette)

        // Step 1: Filter achromatic and extreme-lightness swatches from the
        // chromatic role-selection candidates. Neutral dominance is evaluated
        // separately below against the complete Palette swatch list.
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
        // Scoring uses 90% population and 10% vibrancy. This keeps large
        // background families dominant while still giving saturated colors a
        // moderate lift. Lightness uses a gentle peak around L=0.50, and dark
        // colors below L=0.25 receive a 1.20 bonus.
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
            // Blended score: dominant area (90%) + vibrancy (10%).
            val baseScore   = popFactor * 0.90 + vibrancy * 0.10

            val darkBonus = if (light < 0.25) 1.20 else 1.0
            val score = baseScore * lightFactor * darkBonus
            Scored(sw, score)
        }.sortedByDescending { it.score }

        // Step 4: OKLab clustering — merge swatches that are perceptually similar
        // before coverage/diversity selection. This corrects MMCQ fragmentation:
        // a single
        // dark-family background (Black + Navy + Dark Blue ≈ 48 %) would otherwise
        // lose to a 28 % skin tone because its pixels are split across three small
        // buckets.  After clustering, the merged family competes with its true weight.
        //
        // Clusters are sorted by totalScore (DESC) rather than raw population because
        // totalScore already encodes population, saturation, lightness, and
        // dark bonus, preserving the scoring priorities across the merge
        // boundary.
        val clusters = mergeSimilarSwatches(scored)
            .sortedByDescending { it.totalScore }

        // Step 5: Coverage-driven role selection from top-N clusters.
        //
        // Selecting only by hue could choose three related blue
        // clusters and discard a meaningful warm family. Start with the
        // highest-scoring family, then reward perceptual distance for the next
        // two roles.
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
        // The saturation filter (S ≥ 0.10) above intentionally excludes
        // near-achromatic pixels from chromatic role selection. But
        // for artwork whose BACKGROUND is white, gray, or another near-neutral
        // tone (e.g. an album cover with a bright logo on a white/gray canvas),
        // those background pixels are the majority of the image — yet they were
        // all filtered out, leaving only the small saturated logo to dominate.
        //
        // Fix: after the chromatic roles are chosen, find the most-populated
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
            accentCluster != null -> secondaryCluster?.representativeSwatch?.rgb ?: deriveSecondary(primaryColor)
            else -> deriveSecondary(primaryColor)
        }
        val accentColor = when {
            accentCluster != null -> accentCluster.representativeSwatch.rgb
            secondaryCluster != null -> secondaryCluster.representativeSwatch.rgb
            else -> deriveAccent(primaryColor)
        }

        // Step 7: Highlight + Shadow from remaining clusters.
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
     * AndroidX Palette supplies at most 96 scored swatches. This greedy sweep
     * therefore remains bounded by the configured Palette output size; no extra
     * bitmap decoding or Palette generation is required.
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
