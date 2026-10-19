package dev.wndavenz.music.automix

import dev.wndavenz.music.replaygain.ReplayGainNative

/** Thin JNI surface for AutoMix's C signal-analysis implementation. */
object AutomixNative {
    fun ensureLoaded(): Boolean = ReplayGainNative.ensureLoaded()

    external fun nativeAnalyze(samples: FloatArray, sampleRate: Int): DoubleArray?

    /**
     * Analyzer variant with a global stereo center-channel ratio in [0,1];
     * pass [Double.NaN] when the source is mono or the ratio is unavailable.
     */
    external fun nativeAnalyzeCentered(
        samples: FloatArray,
        sampleRate: Int,
        centerRatio: Double,
    ): DoubleArray?

    /** Returns [startMs, rootPitchClass, qualityId, confidence] rows. */
    external fun nativeAnalyzeChords(samples: FloatArray, sampleRate: Int): DoubleArray?
}
