# ProGuard rules for Compose & Native JNI
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class dev.wndavenz.music.** { *; }
