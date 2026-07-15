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

# JNI bindings — native code (libnative_audio_runtime.so, libreplaygain_native.so)
# calls into these exact class/method names via generated Java_<package>_<Class>_
# <method> symbols. R8 renaming/removing either side breaks the link at runtime
# with an UnsatisfiedLinkError, not a build-time error, so these must stay intact
# even with minifyEnabled/shrinkResources on.
-keepclasseswithmembers class dev.wndavenz.music.effects.NativeDspAudioProcessor {
    native <methods>;
}
-keepclasseswithmembers class dev.wndavenz.music.replaygain.ReplayGainNative {
    native <methods>;
}
-keepclassmembers class dev.wndavenz.music.replaygain.ReplayGainNative {
    *;
}
-keepclasseswithmembers class dev.wndavenz.music.effects.SignalsmithStretchAudioProcessor {
    native <methods>;
}
