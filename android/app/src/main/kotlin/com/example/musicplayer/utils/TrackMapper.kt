package com.example.musicplayer.utils

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

@UnstableApi
object TrackMapper {
    /**
     * Returns the current track map enriched with computed fields (index, artworkUri).
     *
     * During crossfade activeQueueIndex is the source of truth for the current track
     * because the promoted player may briefly report the wrong ExoPlayer index.
     */
    fun currentTrackMap(
        player: ExoPlayer?,
        queue: List<Map<String, Any?>>,
        activeQueueIndex: Int,
        crossfadeDurationSec: Float,
    ): Map<String, Any?>? {
        val p = player ?: return null
        val index = if (crossfadeDurationSec > 0f) activeQueueIndex
                    else p.currentMediaItemIndex
        val songMap = queue.getOrNull(index) ?: return null
        val albumId = (songMap["albumId"] as? Number)?.toLong() ?: 0L
        val artUri = if (albumId > 0)
            "content://media/external/audio/albumart/$albumId" else null
        return songMap + mapOf("index" to index, "artworkUri" to artUri)
    }
}
