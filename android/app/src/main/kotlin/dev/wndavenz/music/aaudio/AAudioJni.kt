package dev.wndavenz.music.aaudio

internal object AAudioJni {
    init { System.loadLibrary("aaudio_engine") }

    external fun create(): Long
    external fun open(handle: Long, path: String): Boolean
    external fun play(handle: Long): Boolean
    external fun pause(handle: Long)
    external fun stop(handle: Long)
    external fun seek(handle: Long, positionMs: Long): Boolean
    external fun setVolume(handle: Long, volume: Float)
    external fun setSpeed(handle: Long, speed: Float)
    external fun setPitch(handle: Long, pitch: Float)
    external fun positionMs(handle: Long): Long
    external fun durationMs(handle: Long): Long
    external fun sampleRate(handle: Long): Int
    external fun channelCount(handle: Long): Int
    external fun release(handle: Long)
}
