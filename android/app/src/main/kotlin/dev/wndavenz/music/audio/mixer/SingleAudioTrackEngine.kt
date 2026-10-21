package dev.wndavenz.music.audio.mixer

import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * Software mix engine with **exactly one hardware output**.
 *
 * Both ExoPlayer decks feed a virtual `DeckAudioSink`; each sink appends
 * post-DSP float stereo frames to its own bounded [PcmRingBuffer]. This engine
 * is the only owner of the shared [SharedAudioOutput] (the real Media3
 * `DefaultAudioSink`): its single output thread consumes both rings at the same
 * frame position, applies per-deck gain, sums, limits the bus and writes one
 * stream to one `AudioTrack`.
 *
 * Why a dedicated thread: Media3's `AudioSink` contract (configure, flush,
 * play/pause, `handleBuffer`, position/EOS) assumes a single caller. Two
 * renderers cannot share it. Here the deck sinks are *virtual*; they never
 * create an `AudioTrack`, and all stateful calls on the hardware sink happen on
 * [engineThread]. Deck-facing setters only publish volatile fields or enqueue a
 * short control command.
 *
 * Time model: the engine writes monotonically increasing bus-frame timestamps
 * to the output sink and derives the audible bus playhead from
 * [SharedAudioOutput.currentPositionUs]. A deck's played position is its
 * consumed frame count minus frames still in flight in the hardware buffer,
 * which keeps every reported media position tied to frames the output actually
 * played rather than to decoder progress.
 */
class SingleAudioTrackEngine(
    private val output: SharedAudioOutput,
    val busSampleRate: Int = BUS_SAMPLE_RATE,
    private val deckCount: Int = DEFAULT_DECK_COUNT,
    private val ringFrames: Int = DEFAULT_RING_FRAMES,
    private val maxBlockFrames: Int = DEFAULT_BLOCK_FRAMES,
    private val log: (String) -> Unit = {},
    /** Runs inside the mix thread before the loop (e.g. audio thread priority). */
    private val onThreadStart: () -> Unit = {},
) : SharedAudioOutput.Listener {

    private class DeckState(val slot: Int) {
        @Volatile
        var stream: DeckStream = DeckStream(0L, 1)

        @Volatile
        var volume: Float = 1f

        @Volatile
        var playing: Boolean = false

        @Volatile
        var released: Boolean = false

        /** Deck-local frames consumed by the mixer for [stream]. */
        @Volatile
        var consumedFrames: Long = 0L

        // Engine-thread-only state.
        var gain: Float = 1f
        var started: Boolean = false
        var lastGeneration: Long = -1L
        var underrunFrames: Long = 0L
        var readScratch: FloatArray = FloatArray(0)
    }

    private val decks = Array(deckCount) { DeckState(it) }
    private val ringLock = Any()
    private val controlQueue = ConcurrentLinkedQueue<() -> Unit>()
    private val busListeners = CopyOnWriteArrayList<SharedAudioOutput.Listener>()

    private val limiter = BusLimiter(sampleRate = busSampleRate)
    private val gainCoefficient = MixGain.smoothingCoefficient(sampleRate = busSampleRate)
    private val mixScratch = FloatArray(maxBlockFrames * PcmRingBuffer.CHANNELS)

    @Volatile
    private var running = true

    @Volatile
    private var busConfigured = false

    @Volatile
    private var outputFailed = false

    @Volatile
    private var busFramesWritten = 0L

    @Volatile
    private var busFramesPlayed = 0L

    @Volatile
    private var busUnderrunFrames = 0L

    @Volatile
    private var sessionId = 0

    @Volatile
    private var activeAudioTracks = 0

    @Volatile
    private var audioTracksCreated = 0L

    @Volatile
    private var audioTracksReleased = 0L

    @Volatile
    private var playingOutput = false

    private var wasPlaying = false

    private var engineThread: Thread? = null

    init {
        requireDeckCount()
        output.listener = this
        engineThread = Thread(::engineLoop, "noisegraph-mix-bus").apply {
            isDaemon = true
            start()
        }
    }

    // ── Deck API (called from ExoPlayer renderer threads) ─────────────────────

    /** Creates / resets the deck for [slot] and returns its new generation. */
    fun addDeck(slot: Int): Long {
        val deck = deck(slot)
        deck.released = false
        return resetDeck(slot)
    }

    /**
     * Replaces the deck stream (flush / seek / track change). The mixer drops
     * any samples from the previous generation; no other deck is touched and
     * the hardware sink is not flushed.
     */
    fun resetDeck(slot: Int): Long {
        val deck = deck(slot)
        synchronized(ringLock) {
            val generation = deck.stream.generation + 1
            deck.stream = DeckStream(generation, ringFrames)
            return generation
        }
    }

    /**
     * Appends post-DSP stereo float frames to a deck. Returns the number of
     * frames accepted (backpressure is reported, never silent loss).
     */
    fun appendFrames(
        slot: Int,
        generation: Long,
        pcm: FloatArray,
        offsetFrames: Int,
        frames: Int,
        sourceStartUs: Long,
        sourceDurationUs: Long,
    ): Int {
        if (frames <= 0) return 0
        val deck = deck(slot)
        val stream = deck.stream
        if (stream.generation != generation) return 0

        val accepted = stream.ring.write(pcm, offsetFrames, frames)
        if (accepted <= 0) return 0

        val duration = if (accepted == frames) {
            sourceDurationUs
        } else {
            sourceDurationUs * accepted / frames
        }
        stream.timeline.append(
            stream.producedFrames,
            accepted,
            sourceStartUs,
            duration,
        )
        stream.producedFrames = stream.producedFrames + accepted
        return accepted
    }

    /** Marks the generation as end-of-stream after its tail was appended. */
    fun finishStream(slot: Int, generation: Long) {
        val stream = deck(slot).stream
        if (stream.generation != generation) return
        stream.eos = true
    }

    fun setDeckVolume(slot: Int, volume: Float) {
        deck(slot).volume = if (volume.isFinite()) volume.coerceIn(0f, 1f) else 1f
    }

    fun setDeckPlaying(slot: Int, playing: Boolean) {
        deck(slot).playing = playing
    }

    fun releaseDeck(slot: Int) {
        val deck = deck(slot)
        deck.playing = false
        deck.released = true
        synchronized(ringLock) {
            deck.stream = DeckStream(deck.stream.generation + 1, 1)
        }
    }

    /**
     * Flushes the shared hardware buffer after a seek on [slot], but only when
     * no other deck is playing and no deck still has unplayed frames.
     *
     * Without this, the samples already written to the single AudioTrack would
     * keep playing for up to one hardware buffer (~100-250 ms) after the user
     * seeks. During an overlap the bus must NOT be flushed: the other deck's
     * queued audio would be lost, which is why the guard is strict.
     */
    fun flushBusForSeek(slot: Int) {
        executeOnOutputThread {
            val otherPlaying = decks.any { it.slot != slot && it.playing && !it.released }
            if (otherPlaying) return@executeOnOutputThread
            val unplayed = decks.any { deck ->
                val stream = deck.stream
                stream.producedFrames > 0L &&
                    playedLocalFrames(deck, stream) < stream.producedFrames
            }
            if (unplayed) return@executeOnOutputThread

            output.flush()
            busFramesWritten = 0L
            busFramesPlayed = 0L
            for (deck in decks) {
                // Decks other than the seeked one are fully played (guard
                // above); mark their consumed counter at their produced
                // total so they do not look like they have pending data.
                // lastGeneration stays untouched: the generations themselves
                // did not change, and resetting it would make an idle deck
                // look unplayed again.
                deck.consumedFrames = deck.stream.producedFrames
            }
            limiter.reset()
        }
    }

    /** Frames that may be appended right now for a deck generation. */
    fun deckFreeFrames(slot: Int, generation: Long): Int {
        val stream = deck(slot).stream
        if (stream.generation != generation) return 0
        return stream.ring.availableToWrite
    }

    /**
     * Audible media position of a deck in µs, or a negative value when the
     * deck has not produced anything yet.
     */
    fun deckPositionUs(slot: Int, sourceEnded: Boolean): Long {
        val deck = deck(slot)
        val stream = deck.stream
        val produced = stream.producedFrames
        if (produced <= 0L) return -1L
        val played = playedLocalFrames(deck, stream)
        if (sourceEnded && played >= produced) {
            return stream.timeline.endPositionUs() ?: -1L
        }
        return stream.timeline.positionAt(played) ?: -1L
    }

    fun deckHasPendingData(slot: Int): Boolean {
        val deck = deck(slot)
        val stream = deck.stream
        return playedLocalFrames(deck, stream) < stream.producedFrames
    }

    fun deckIsEnded(slot: Int): Boolean {
        val deck = deck(slot)
        val stream = deck.stream
        return stream.eos && playedLocalFrames(deck, stream) >= stream.producedFrames
    }

    // ── Shared output control (engine thread discipline) ─────────────────────

    /**
     * Configures the single bus output. Safe to call from a renderer thread:
     * the command runs on the engine thread and this call blocks until it is
     * done (configuration happens once per service session, before playback).
     */
    fun configureOutput(): Boolean {
        if (busConfigured) return true
        val latch = CountDownLatch(1)
        var configured = false
        executeOnOutputThread {
            if (!busConfigured) {
                configured = output.configure(BUS_SAMPLE_RATE, PcmRingBuffer.CHANNELS)
                if (configured) {
                    busConfigured = true
                    log(
                        "Mixer bus configured: ${BUS_SAMPLE_RATE}Hz stereo float, " +
                            "one shared output sink",
                    )
                } else {
                    log("Mixer bus configuration FAILED at ${BUS_SAMPLE_RATE}Hz")
                }
            } else {
                configured = true
            }
            latch.countDown()
        }
        return if (latch.await(CONFIGURE_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
            configured && busConfigured
        } else {
            log("Mixer bus configuration timed out")
            false
        }
    }

    /** Runs [command] on the engine output thread. Runs inline when already there. */
    fun executeOnOutputThread(command: () -> Unit) {
        if (Thread.currentThread() === engineThread) {
            command()
        } else {
            controlQueue.add(command)
        }
    }

    fun addBusListener(listener: SharedAudioOutput.Listener) {
        busListeners.addIfAbsent(listener)
    }

    fun removeBusListener(listener: SharedAudioOutput.Listener) {
        busListeners.remove(listener)
    }

    fun hasOutputFailed(): Boolean = outputFailed

    fun metrics(): MixerMetrics = MixerMetrics(
        activeAudioTracks = activeAudioTracks,
        audioTracksCreated = audioTracksCreated,
        audioTracksReleased = audioTracksReleased,
        busFramesWritten = busFramesWritten,
        busFramesPlayed = busFramesPlayed,
        busUnderrunFrames = busUnderrunFrames,
        sessionId = sessionId,
    )

    /** Stops the engine and releases the shared output. Idempotent. */
    fun release() {
        if (!running) {
            output.release()
            return
        }
        val latch = CountDownLatch(1)
        executeOnOutputThread {
            output.release()
            running = false
            latch.countDown()
        }
        latch.await(RELEASE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        running = false
        engineThread?.let { thread ->
            thread.interrupt()
            try {
                thread.join(RELEASE_TIMEOUT_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        engineThread = null
        busListeners.clear()
        log("Mixer released: ${metrics()}")
    }

    // ── SharedAudioOutput.Listener (already on the engine thread) ────────────

    override fun onUnderrun(
        bufferSizeBytes: Int,
        bufferSizeMs: Long,
        elapsedSinceLastFeedMs: Long,
    ) {
        log(
            "Mixer underrun: buffer=${bufferSizeBytes}B/${bufferSizeMs}ms " +
                "sinceLastFeed=${elapsedSinceLastFeedMs}ms",
        )
        for (listener in busListeners) {
            listener.onUnderrun(bufferSizeBytes, bufferSizeMs, elapsedSinceLastFeedMs)
        }
    }

    override fun onPositionDiscontinuity() {
        for (listener in busListeners) listener.onPositionDiscontinuity()
    }

    override fun onAudioSessionIdChanged(audioSessionId: Int) {
        sessionId = audioSessionId
        for (listener in busListeners) listener.onAudioSessionIdChanged(audioSessionId)
    }

    override fun onAudioTrackInitialized(
        encoding: Int,
        sampleRate: Int,
        channelConfig: Int,
        bufferSize: Int,
    ) {
        activeAudioTracks++
        audioTracksCreated++
        log(
            "AudioTrack initialized: encoding=$encoding rate=$sampleRate " +
                "channelConfig=$channelConfig buffer=$bufferSize " +
                "activeAudioTrackCount=$activeAudioTracks",
        )
        for (listener in busListeners) {
            listener.onAudioTrackInitialized(encoding, sampleRate, channelConfig, bufferSize)
        }
    }

    override fun onAudioTrackReleased(
        encoding: Int,
        sampleRate: Int,
        channelConfig: Int,
    ) {
        activeAudioTracks = (activeAudioTracks - 1).coerceAtLeast(0)
        audioTracksReleased++
        log("AudioTrack released: activeAudioTrackCount=$activeAudioTracks")
        for (listener in busListeners) {
            listener.onAudioTrackReleased(encoding, sampleRate, channelConfig)
        }
    }

    override fun onSinkError(message: String) {
        log("Mixer sink report: $message")
        for (listener in busListeners) listener.onSinkError(message)
    }

    override fun onError(message: String) {
        outputFailed = true
        log("Mixer output error: $message")
        for (listener in busListeners) listener.onError(message)
    }

    // ── Engine thread ────────────────────────────────────────────────────────

    private fun engineLoop() {
        try {
            onThreadStart()
        } catch (_: Exception) {
            // Priority hints are best-effort.
        }
        while (running) {
            try {
                drainControlQueue()
                // release() can be executed by a queued command; do not touch
                // the sink after it has been released.
                if (!running) return

                val anyPlaying = decks.any { it.playing && !it.released }
                if (anyPlaying && !wasPlaying) {
                    limiter.reset()
                }
                wasPlaying = anyPlaying

                if (!busConfigured || outputFailed || !anyPlaying) {
                    if (playingOutput && (!anyPlaying || outputFailed)) {
                        output.pause()
                        playingOutput = false
                    }
                    wasPlaying = false
                    sleepQuietly(IDLE_SLEEP_MS)
                    continue
                }

                if (!playingOutput) {
                    output.play()
                    playingOutput = true
                }

                updateBusPlayhead()
                mixBlock()
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            } catch (error: Exception) {
                log("Mixer loop error: ${error.message}")
                sleepQuietly(ERROR_SLEEP_MS)
            }
        }
    }

    private fun drainControlQueue() {
        while (true) {
            val command = controlQueue.poll() ?: return
            try {
                command()
            } catch (error: Exception) {
                log("Mixer control error: ${error.message}")
            }
        }
    }

    private fun mixBlock(): Boolean {
        val toMix = decks.filter { it.playing && !it.released }
        if (toMix.isEmpty()) return false

        for (deck in toMix) {
            val stream = deck.stream
            if (deck.lastGeneration != stream.generation) {
                deck.lastGeneration = stream.generation
                deck.consumedFrames = 0L
                deck.gain = deck.volume
                deck.started = false
                val needed = maxBlockFrames * PcmRingBuffer.CHANNELS
                if (deck.readScratch.size < needed) deck.readScratch = FloatArray(needed)
            }
        }

        var starved = false
        for (deck in toMix) {
            val stream = deck.stream
            val monitoring = deck.started && !stream.eos
            if (monitoring && stream.ring.availableToRead == 0) {
                starved = true
                deck.underrunFrames++
                break
            }
        }

        if (starved) {
            // Give the decoder a short grace period. If it still has not
            // produced anything, write silence for the whole bus without
            // consuming the other deck: this preserves A/B alignment instead
            // of advancing one deck alone.
            sleepQuietly(UNDERRUN_GRACE_MS)
            val stillStarved = toMix.any {
                it.started && !it.stream.eos && it.stream.ring.availableToRead == 0
            }
            if (!stillStarved) return false
            busUnderrunFrames += maxBlockFrames.toLong()
            writeSilence(maxBlockFrames)
            return true
        }

        var frames = maxBlockFrames
        var anyData = false
        for (deck in toMix) {
            val available = deck.stream.ring.availableToRead
            if (available > 0) {
                anyData = true
                frames = min(frames, available)
            }
        }
        if (!anyData) {
            // All contributing decks are EOS and drained (or still waiting for
            // their first decoded buffer). Nothing to schedule right now.
            return false
        }

        java.util.Arrays.fill(
            mixScratch,
            0,
            frames * PcmRingBuffer.CHANNELS,
            0f,
        )

        for (deck in toMix) {
            val stream = deck.stream
            val framesForDeck = min(frames, stream.ring.availableToRead)
            if (framesForDeck <= 0) continue

            val read = stream.ring.read(deck.readScratch, 0, framesForDeck)
            if (read <= 0) continue

            var gain = deck.gain
            val target = deck.volume
            val scratch = deck.readScratch
            for (frame in 0 until read) {
                gain += (target - gain) * gainCoefficient
                val base = frame * PcmRingBuffer.CHANNELS
                mixScratch[base] += scratch[base] * gain
                mixScratch[base + 1] += scratch[base + 1] * gain
            }
            deck.gain = gain
            deck.consumedFrames += read
            deck.started = true
            stream.timeline.trimBefore(deck.consumedFrames)
        }

        limiter.process(mixScratch, frames)

        val presentationTimeUs = busFramesWritten * 1_000_000L / busSampleRate
        val accepted = output.handleBuffer(mixScratch, frames, presentationTimeUs)
        if (!accepted) {
            log("Mixer output rejected a block")
            outputFailed = true
            return false
        }

        busFramesWritten += frames
        updateBusPlayhead()
        return true
    }

    private fun writeSilence(frames: Int) {
        java.util.Arrays.fill(
            mixScratch,
            0,
            frames * PcmRingBuffer.CHANNELS,
            0f,
        )
        val presentationTimeUs = busFramesWritten * 1_000_000L / busSampleRate
        if (output.handleBuffer(mixScratch, frames, presentationTimeUs)) {
            busFramesWritten += frames
            updateBusPlayhead()
        } else {
            outputFailed = true
        }
    }

    private fun updateBusPlayhead() {
        val positionUs = output.currentPositionUs()
        if (positionUs < 0L) return
        val played = positionUs * busSampleRate / 1_000_000L
        busFramesPlayed = played.coerceIn(0L, busFramesWritten)
    }

    private fun playedLocalFrames(deck: DeckState, stream: DeckStream): Long {
        val produced = stream.producedFrames
        val consumed = deck.consumedFrames
        val pending = (busFramesWritten - busFramesPlayed).coerceAtLeast(0L)
        val inFlight = min(pending, consumed)
        return (consumed - inFlight).coerceIn(0L, produced)
    }

    private fun deck(slot: Int): DeckState {
        require(slot in decks.indices) { "Unknown deck slot $slot" }
        return decks[slot]
    }

    private fun requireDeckCount() {
        require(deckCount > 0) { "deckCount must be > 0" }
        require(busSampleRate in 8_000..192_000) { "busSampleRate out of range" }
        require(ringFrames > 0) { "ringFrames must be > 0" }
        require(maxBlockFrames > 0) { "maxBlockFrames must be > 0" }
        require(maxBlockFrames <= ringFrames) { "block larger than ring" }
    }

    private fun sleepQuietly(millis: Long) {
        try {
            Thread.sleep(millis)
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            throw interrupted
        }
    }

    companion object {
        /** Fallback software mix rate; the service prefers the device output rate. */
        const val BUS_SAMPLE_RATE = 48_000

        /** 500 ms of stereo float headroom per deck. */
        const val DEFAULT_RING_FRAMES = BUS_SAMPLE_RATE / 2

        /** 10 ms mix quanta keep gain updates and control latency low. */
        const val DEFAULT_BLOCK_FRAMES = BUS_SAMPLE_RATE / 100

        const val DEFAULT_DECK_COUNT = 2

        private const val IDLE_SLEEP_MS = 3L
        private const val ERROR_SLEEP_MS = 20L
        private const val UNDERRUN_GRACE_MS = 10L
        private const val CONFIGURE_TIMEOUT_MS = 3_000L
        private const val RELEASE_TIMEOUT_MS = 1_500L

        /**
         * Runtime kill switch. When false the service keeps the legacy
         * per-deck `DefaultAudioSink` path (two AudioTracks, mixed by
         * AudioFlinger). Flip before players are created to roll back.
         */
        @Volatile
        var enabled: Boolean = true
    }
}
