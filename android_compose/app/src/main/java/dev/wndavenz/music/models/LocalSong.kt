package dev.wndavenz.music.models

data class LocalSong(
    val id: Int,
    val title: String,
    val artist: String,
    val path: String,
    val album: String,
    val albumId: Int,
    val artworkUri: String? = null,
    val durationMs: Long = 0L,
    val year: Int? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val albumArtist: String? = null,
    val genre: String? = null,
    val bitrate: Int? = null,
    val sampleRate: Int? = null,
    val dateAdded: Int? = null,
)
