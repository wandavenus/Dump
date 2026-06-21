package com.example.musicplayer.utils

object TrackMapper {
    fun currentTrack(queue: List<Map<String, Any?>>, index: Int): Map<String, Any?>? {
        val songMap = queue.getOrNull(index) ?: return null
        val albumId = (songMap["albumId"] as? Number)?.toLong() ?: 0L
        val artUri = if (albumId > 0) "content://media/external/audio/albumart/$albumId" else null
        return songMap + mapOf("index" to index, "artworkUri" to artUri)
    }
}
