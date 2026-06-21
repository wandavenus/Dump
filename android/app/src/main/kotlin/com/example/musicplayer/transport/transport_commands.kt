package com.example.musicplayer.transport

import androidx.media3.common.Player

object TransportCommands {
    fun processingState(player: Player): String = when (player.playbackState) {
        Player.STATE_BUFFERING -> "buffering"
        Player.STATE_READY -> "ready"
        Player.STATE_ENDED -> "completed"
        else -> "idle"
    }
    fun repeatMode(player: Player): String = when (player.repeatMode) {
        Player.REPEAT_MODE_ONE -> "one"
        Player.REPEAT_MODE_ALL -> "all"
        else -> "off"
    }
}
