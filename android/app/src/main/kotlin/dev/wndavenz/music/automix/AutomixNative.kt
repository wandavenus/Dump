package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.ReplayGainNative

/** Thin JNI surface for AutoMix's C signal-analysis implementation. */
object AutomixNative {
    fun ensureLoaded(): Boolean = ReplayGainNative.ensureLoaded()

    external fun nativeAnalyze(samples: FloatArray, sampleRate: Int): DoubleArray?

    /** Returns [startMs, rootPitchClass, qualityId, confidence] rows. */
    external fun nativeAnalyzeChords(samples: FloatArray, sampleRate: Int): DoubleArray?
}
