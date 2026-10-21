package dev.wndavenz.music.audio.mixer;

import java.nio.ByteBuffer;

/**
 * Minimal host-side mirror of the Kotlin JNI surface. Only used to exercise
 * pcm_native_jni.cpp on a desktop JVM; the app uses the Kotlin object.
 */
public final class NativePcmBridge {
    static {
        System.loadLibrary("pcm_mixer_native");
    }

    private NativePcmBridge() {}

    public static native long nativeCreateDeckConverter(int inputRate, int outputRate);
    public static native void nativeDestroyDeckConverter(long handle);
    public static native void nativeResetDeckConverter(long handle);
    public static native int nativeDeckOutputFramesUpperBound(long handle, int inputFrames);
    public static native int nativeProcessDeck(
        long handle,
        ByteBuffer input,
        int offsetBytes,
        int inputFrames,
        int channels,
        int format,
        boolean bigEndian,
        float[] output);

    public static native long nativeCreateMixer(int sampleRate, int maxBlockFrames);
    public static native void nativeDestroyMixer(long handle);
    public static native void nativeResetMixer(long handle);
    public static native boolean nativeMix(
        long handle,
        int activeMask,
        float[] deck0,
        float[] deck1,
        float[] gains,
        float[] targets,
        float[] output,
        int frames);
}
