---
name: Flutter refinement roadmap
description: Long-term decision to keep Flutter and improve the existing Flutter/native architecture incrementally.
---

Flutter tetap menjadi framework utama aplikasi. Migrasi penuh ke Jetpack Compose
ditunda dan tidak menjadi sasaran pekerjaan berikutnya kecuali user meminta
kembali secara eksplisit.

**Why:** UI Flutter, Media3/Kotlin, native DSP, queue, lyrics, artwork, dan
notification sudah terintegrasi. Migrasi penuh akan membuka risiko regresi audio
dan membutuhkan penulisan ulang sebagian besar UI serta state management.

**How to apply:** prioritaskan stabilitas startup, konsistensi state playback,
pengujian Xiaomi Mi 9T/K20, optimasi artwork/lyrics/animation, validasi DSP
default-off, penyempurnaan Settings, serta regression testing. Gunakan
`ROADMAP_PENYEMPURNAAN_FLUTTER.md` sebagai urutan kerja tingkat tinggi.