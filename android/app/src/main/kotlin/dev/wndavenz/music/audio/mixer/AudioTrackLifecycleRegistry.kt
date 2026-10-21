package dev.wndavenz.music.audio.mixer

import java.util.ArrayDeque
import java.util.IdentityHashMap
import java.util.LinkedHashMap

/**
 * Process-wide lifecycle accounting for AudioTracks owned by this app's Media3 sinks.
 *
 * A sink callback identifies the owner but does not expose the framework AudioTrack
 * object itself. We therefore pair each owner's initialize/release callbacks in
 * FIFO order, assign diagnostic IDs, and count all tracks that Media3 reports as
 * alive at the same time. Virtual deck sinks must not report hardware lifecycle
 * callbacks; only physical sinks should call this registry.
 */
object AudioTrackLifecycleRegistry {
    data class Snapshot(
        val activeCount: Int,
        val totalCreated: Long,
        val totalReleased: Long,
        val peakConcurrent: Int,
        val unmatchedReleaseCallbacks: Long,
        val activeOwners: List<String>,
    )

    private data class Track(
        val id: Long,
        val ownerLabel: String,
        val encoding: Int,
        val sampleRate: Int,
        val channelConfig: Int,
        val bufferSize: Int,
    )

    private val lock = Any()
    private var nextTrackId = 0L
    private val activeTracks = LinkedHashMap<Long, Track>()
    private val ownerTrackIds = IdentityHashMap<Any, ArrayDeque<Long>>()

    private var totalCreated = 0L
    private var totalReleased = 0L
    private var peakConcurrent = 0
    private var unmatchedReleaseCallbacks = 0L

    fun onInitialized(
        owner: Any,
        ownerLabel: String,
        encoding: Int,
        sampleRate: Int,
        channelConfig: Int,
        bufferSize: Int,
    ): String = synchronized(lock) {
        val id = ++nextTrackId
        val track = Track(
            id = id,
            ownerLabel = ownerLabel,
            encoding = encoding,
            sampleRate = sampleRate,
            channelConfig = channelConfig,
            bufferSize = bufferSize,
        )
        ownerTrackIds.getOrPut(owner) { ArrayDeque() }.addLast(id)
        activeTracks[id] = track
        totalCreated++
        if (activeTracks.size > peakConcurrent) peakConcurrent = activeTracks.size
        event(
            kind = "CREATED",
            track = track,
            ownerLabel = ownerLabel,
        )
    }

    fun onReleased(owner: Any, ownerLabel: String): String = synchronized(lock) {
        val queue = ownerTrackIds[owner]
        val id = queue?.pollFirst()
        if (queue != null && queue.isEmpty()) ownerTrackIds.remove(owner)

        if (id == null) {
            unmatchedReleaseCallbacks++
            return@synchronized "HW_AUDIO_TRACK_RELEASE_UNMATCHED owner=$ownerLabel " +
                "active=${activeTracks.size} created=$totalCreated released=$totalReleased " +
                "peakConcurrent=$peakConcurrent unmatched=$unmatchedReleaseCallbacks"
        }

        val track = activeTracks.remove(id)
        if (track == null) {
            unmatchedReleaseCallbacks++
            return@synchronized "HW_AUDIO_TRACK_RELEASE_UNMATCHED owner=$ownerLabel id=$id " +
                "active=${activeTracks.size} created=$totalCreated released=$totalReleased " +
                "peakConcurrent=$peakConcurrent unmatched=$unmatchedReleaseCallbacks"
        }

        totalReleased++
        event(kind = "RELEASED", track = track, ownerLabel = ownerLabel)
    }

    fun snapshot(): Snapshot = synchronized(lock) {
        Snapshot(
            activeCount = activeTracks.size,
            totalCreated = totalCreated,
            totalReleased = totalReleased,
            peakConcurrent = peakConcurrent,
            unmatchedReleaseCallbacks = unmatchedReleaseCallbacks,
            activeOwners = activeTracks.values.map { it.ownerLabel },
        )
    }

    private fun event(kind: String, track: Track, ownerLabel: String): String {
        val liveOwners = activeTracks.values.joinToString(
            prefix = "[",
            postfix = "]",
            separator = ",",
        ) { "${it.ownerLabel}#${it.id}" }
        return "HW_AUDIO_TRACK_$kind id=${track.id} owner=$ownerLabel " +
            "encoding=${track.encoding} rate=${track.sampleRate}Hz " +
            "channelConfig=${track.channelConfig} buffer=${track.bufferSize} " +
            "active=${activeTracks.size} created=$totalCreated released=$totalReleased " +
            "peakConcurrent=$peakConcurrent live=$liveOwners"
    }

    /** Resets singleton state for deterministic local unit tests only. */
    internal fun resetForTests() = synchronized(lock) {
        nextTrackId = 0L
        activeTracks.clear()
        ownerTrackIds.clear()
        totalCreated = 0L
        totalReleased = 0L
        peakConcurrent = 0
        unmatchedReleaseCallbacks = 0L
    }
}
