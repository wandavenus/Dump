package dev.wndavenz.music.models

data class Playlist(
    val id: String,
    val name: String,
    val songIds: List<Int>,
    val createdAt: Long,
)
