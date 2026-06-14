---
name: Hi-Res Audio mode
description: Mode 2 adalah Hi-Res Audio (sebelumnya MIUI Hi-Fi); enableHiRes() coba 5 pendekatan berbeda untuk kompatibilitas OEM.
---

## AudioManager parameters (mode 2 → enable=true)
```kotlin
am.setParameters("hifi_audio=on")           // MIUI, beberapa Qualcomm
am.setParameters("high_resolution_audio=on") // standard Android
am.setParameters("hifi_enable=on")           // beberapa MediaTek
am.setParameters("audio_qoe_enable=on")      // Sony
am.setParameters("hi_res_audio_enabled=on")  // Qualcomm alt
```

## MIUI broadcast
```kotlin
sendBroadcast(Intent("miui.intent.action.ACTION_HEADSET_HIFI_ENABLE")
    .apply { setPackage("com.android.phone") })
```

## ContentResolver (MIUI, perlu WRITE_SETTINGS)
```kotlin
Settings.System.putString(contentResolver, "hifi_audio", "1")
```

## Semua dalam try-catch
Setiap metode independent try-catch — gagal di non-MIUI device secara silent.

## Snackbar
"Hi-Res: Pastikan headset hi-res terhubung. Di MIUI: Pengaturan → Suara → HiFi Audio."

**Why:** Tidak ada API Android standar universal untuk Hi-Res; setiap OEM punya cara sendiri. Multi-approach paling kompatibel untuk MIUI 12, Qualcomm, Sony di Android 11.
