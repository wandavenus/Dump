package com.example.musicplayer.utils

import android.net.Uri
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

object MediaItemFactory {
    fun from(map: Map<*, *>): MediaItem {
        val path = map["path"] as? String ?: ""
        val uri = if (path.startsWith("content://") || path.startsWith("file://")) path.toUri() else Uri.fromFile(java.io.File(path))
        val albumId = (map["albumId"] as? Number)?.toLong() ?: 0L
        val artworkUri = if (albumId > 0) Uri.parse("content://media/external/audio/albumart/$albumId") else null
        val metaBuilder = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setAlbumTitle(map["album"] as? String)
        if (artworkUri != null) metaBuilder.setArtworkUri(artworkUri)
        return MediaItem.Builder()
            .setMediaId((map["id"] ?: path).toString())
            .setUri(uri)
            .setMediaMetadata(metaBuilder.build())
            .build()
    }
}
