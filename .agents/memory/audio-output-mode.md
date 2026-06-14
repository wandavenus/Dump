---
name: AudioOutputMode
description: 3 mode output audio: Auto/AAudio, OpenSL ES, MIUI Hi-Fi; LoudnessEnhancer.setTargetGain() butuh double.
---

## Mode
- 0 = Auto/AAudio: default ExoPlayer, direkomendasikan Android 8+
- 1 = OpenSL ES: stored preference; ExoPlayer uses OpenSL ES on older devices anyway
- 2 = MIUI Hi-Fi: kirim broadcast `miui.intent.action.ACTION_HEADSET_HIFI_ENABLE` + ContentResolver write ke `hifi_audio`

## MIUI Hi-Fi
```kotlin
val intent = Intent("miui.intent.action.ACTION_HEADSET_HIFI_ENABLE")
intent.setPackage("com.android.phone")
sendBroadcast(intent)
// fallback:
Settings.System.putString(contentResolver, "hifi_audio", "1")
```
Gagal di non-MIUI device secara silent (dalam try-catch).

## LoudnessEnhancer Type Bug
`AndroidLoudnessEnhancer.setTargetGain()` di just_audio 0.9.x expects `double` bukan `int`.
Default: `300.0` millibels (+3 dB gentle normalize). Off = `0.0`.

**Why:** MIUI 12 memblokir banyak AudioEffect API; semua effect creation harus dalam try-catch. AudioEffect.queryEffects() digunakan untuk cek hardware support sebelum membuat instance.
