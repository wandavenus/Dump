---
name: AutoMix automatic controls
description: User requirement that AutoMix mixing controls operate automatically.
---

Kontrol AutoMix harus berjalan otomatis; pengguna tidak perlu mengatur parameter
mixing secara manual.

**Why:** Pengguna memprioritaskan suara transisi DJ dan meminta semua kontrol
dibuat otomatis.

**How to apply:** Turunkan perilaku transisi dari analisis pasangan lagu dan
pertahankan fallback aman saat hasil analisis tidak meyakinkan.

Stage bass-swap dan filter ekor per-deck berjalan di native C; pada ARM64 stereo
gunakan kernel NEON, dan kanal lain memakai fallback C. State filter dan target
gain harus tetap terisolasi per physical stream slot; kontrol lintas-thread
menggunakan atomik, sedangkan pemrosesan audio tidak mengalokasikan atau mengunci.

**Why:** Dua ExoPlayer dapat memproses PCM bersamaan selama overlap, sehingga
state filter bersama akan mencemari suara kedua deck. Memindahkan loop sampel
ke native juga menghindari kerja per-sampel pada Kotlin/JVM.

**How to apply:** Pertahankan stream slot terpisah untuk primary/standby,
unity-gain sebagai jalur transparan, serta scalar fallback untuk format selain
stereo sebelum menambah automasi tone AutoMix lainnya. Android CMake harus
mendeklarasikan bahasa ASM agar berkas `.S` yang sudah terdaftar benar-benar
dikompilasi dan kernel NEON tidak menjadi simbol hilang saat link.

Koreksi beat-phase saat dua dek overlap dihitung oleh `automix_phase_lock.c`
melalui JNI, bukan diduplikasi di Kotlin. Jika library/simbol native tidak ada,
lewati koreksi dan biarkan crossfade biasa lanjut; uji rumus phase-lock di host
native C test.

**Why:** Penghitungan berkala selama crossfade harus memakai satu implementasi
native yang sama dengan tes, sementara kegagalan pemuatan JNI tidak boleh
menghentikan audio.

**How to apply:** Perubahan phase-lock harus mengubah fungsi C dan tes C
bersama-sama; Kotlin hanya meneruskan posisi/BPM dan menerapkan faktor tempo.
