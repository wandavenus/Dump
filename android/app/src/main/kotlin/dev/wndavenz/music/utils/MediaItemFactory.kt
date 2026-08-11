package dev.wndavenz.music.utils

import android.net.Uri
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi

@UnstableApi
object MediaItemFactory {
    /**
     * Converts a Flutter song map into a Media3 MediaItem.
     * Supports content://, file://, and raw filesystem paths.
     */
    fun from(map: Map<*, *>): MediaItem {
        val path = map["path"] as? String ?: ""
        val uri = when {
            path.startsWith("content://") || path.startsWith("file://") -> path.toUri()
            else -> Uri.fromFile(java.io.File(path))
        }

        // ZOOM-01: do NOT set MediaMetadata.artworkUri. The only URI we could
        // attach is the low-res MediaStore album-art thumbnail
        // (content://media/external/audio/albumart/{albumId}, often ≤512 px,
        // non-square) — SystemUI / MIUI media surfaces decode ART_URI and
        // upscale + center-crop it → the "artwork zooms / pixelates when
        // playing" bug. High-res square art is published separately as
        // artworkData (SessionArtworkProvider / publishSessionArtwork); with
        // no ART_URI in the metadata, a renderer can only show artworkData or
        // no art — never the blown-up thumbnail.
        val metaBuilder = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setAlbumTitle(map["album"] as? String)

        return MediaItem.Builder()
            .setMediaId((map["id"] ?: path).toString())
            .setUri(uri)
            .setMediaMetadata(metaBuilder.build())
            .build()
    }
}
