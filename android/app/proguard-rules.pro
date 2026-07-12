# Project-specific ProGuard / R8 rules.
#
# Default optimization rules are provided by:
#   proguard-android-optimize.txt
#
# Add custom -keep rules here only when required by reflection,
# serialization, JNI, or third-party libraries.

# Media3 FFmpeg decoder extension is discovered by DefaultRenderersFactory via
# reflection. Keep the renderer, library wrapper, decoder classes, and native
# method names so release builds can instantiate FfmpegAudioRenderer and load
# libffmpegJNI.so.
-keep class androidx.media3.decoder.ffmpeg.** { *; }
