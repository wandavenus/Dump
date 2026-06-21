package com.example.musicplayer.transport

data class TransportState(
    val playing: Boolean,
    val processingState: String,
    val positionMs: Long,
    val durationMs: Long,
    val currentIndex: Int,
    val repeatMode: String,
    val shuffleEnabled: Boolean,
)
