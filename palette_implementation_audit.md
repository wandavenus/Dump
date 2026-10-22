# Audit Implementasi Palette Color Background & Artwork — final (2026-10-22)

**Status:** Audit dan perbaikan selesai di working tree. Seluruh temuan Medium/Low ditutup; tidak ada temuan Tinggi.
**Repository:** `wandavenus/Dump`
**Basis kode:** `e8ea971` (`main`)
**Perubahan working tree sebelum laporan:** 19 berkas terlacak (+481/−142), 3 berkas kode/test baru (304 baris), dan laporan ini.
**Metode:** pembacaan kode Dart/Kotlin, penelusuran call-site, pembandingan kontrak channel, penelusuran cache/persistensi, dan pemeriksaan test yang ada.
**Batasan:** Flutter, Java, dan Gradle tidak tersedia di lingkungan ini. `flutter analyze`, `flutter test`, dan `./gradlew testDebugUnitTest` **tidak dapat dijalankan**. Verifikasi yang dilakukan hanya `dart format` (parsing sintaks) dan penelusuran statis manual.

## Ringkasan eksekutif

Jalur palette memiliki arsitektur yang sehat: ekstraksi native 5-peran, deduplikasi berlapis, cache LRU + disk berversi, watchdog callback, dan fallback yang tidak dipersistensi. Audit menemukan 15 masalah (5 Medium, 10 Low) pada ketahanan startup, lifecycle widget, invalidation artwork, persistensi, aksesibilitas kontras, dan pemeliharaan klaster warna. Semuanya diperbaiki di working tree.

Putaran perbaikan juga menemukan dua cacat algoritma tambahan yang belum masuk katalog awal: artwork yang sepenuhnya netral jatuh ke padding warna biru hard-fallback, dan derivasi highlight/shadow untuk primary netral memaksa saturasi minimum sehingga abu-abu memperoleh hue merah. Keduanya diperbaiki dan `CACHE_VERSION` dinaikkan dari 8 ke 9.

| ID | Severity | Topik | Status |
|---|---|---|---|
| P-01 | Medium | Blur menampilkan artwork lagu sebelumnya saat lagu baru tanpa artwork | Fixed |
| P-02 | Medium | Cache palette korup dapat melempar `TypeError` dan melewati `runApp()` | Fixed |
| P-03 | Medium | Tidak ada timeout Dart untuk ekstraksi native | Fixed |
| P-04 | Medium | Prefetch palette tetap berjalan pada mode `artworkBlur` | Fixed |
| P-05 | Low | Race palette async pada kartu album yang didaur ulang | Fixed |
| P-06 | Low | Palette tidak di-invalidate saat artwork di-evict | Fixed |
| P-07 | Low | Teks putih hardcoded di atas primary palette terang | Fixed |
| P-08 | Low | Tulisan persistensi dapat bertumpuk pada `$path.tmp` yang sama | Fixed |
| P-09 | Low | Blur tidak retry setelah `lease == null` | Fixed |
| P-10 | Low | `FragmentShader` tidak pernah di-dispose | Fixed |
| P-11 | Low | Dokumentasi/memory drift (ukuran blur, jumlah thread, referensi lama) | Fixed |
| P-12 | Low | Greedy any-member clustering dapat chain-merge keluarga berbeda | Fixed |
| P-13 | Low | Coverage test palette minim | Fixed (test ditambahkan; belum dieksekusi) |
| P-14 | Medium | Artwork netral penuh mendapat padding biru hard-fallback | Fixed |
| P-15 | Low | Primary netral menghasilkan highlight/shadow ber-hue merah | Fixed |

## Cakupan

- Mode background `PlayerBackgroundStyle.fluid` (shader palette) dan `artworkBlur` (blur artwork).
- Sumber palette: `NativePaletteService` + `NativePaletteBridge.kt` + `NativePaletteModels.kt`.
- Panel warna kartu album di Home yang memakai primary palette.
- Cache memori/disk, invalidation artwork, prefetch playback, dan lifecycle shader/blur.
- Dokumentasi dan memory yang menjelaskan kontrak di atas.

Tidak diaudit: kualitas estetika akhir pada perangkat, performa GPU terukur, dan algoritma AutoMix (lihat audit terpisah).

## Temuan rinci

### P-01 — Artwork blur menampilkan cover lagu sebelumnya (Fixed)

**Lokasi:** `lib/widgets/player/player_background/cover_blur.dart:142-168`.
**Akar masalah:** `_loadArtwork` langsung `return` ketika `provider == null`. `_provider`, `_providerSongId`, `_blurLease`, dan `_requestedBlurKey` tetap menunjuk lagu lama. `build` hanya memakai fallback bila provider **dan** cached image sama-sama null, sehingga cover lagu sebelumnya tetap tampil untuk lagu baru tanpa artwork.
**Dampak:** Background blur menunjukkan artwork yang salah secara persistif, bukan sekadar flash sementara.
**Perbaikan:** Setelah lookup selesai dan masih menjadi request aktif, provider null membersihkan provider + lease + key, menaikkan `_blurRequestId`, dan melepas lease lama. Frame lama tetap dipertahankan hanya selama lookup berlangsung (mencegah flash hitam).
**Verifikasi:** Logika alur dibaca ulang; belum ada widget test khusus karena `ArtworkRepository` adalah singleton tanpa seam injeksi.

### P-02 — Cache korup dapat menggagalkan startup (Fixed)

**Lokasi:** `lib/services/native_palette_service.dart:89-181`.
**Akar masalah:** `warmUp` memakai `jsonDecode(raw) as Map<String, dynamic>` dan `values[i] as int`. Root JSON non-object atau elemen non-int/out-of-range melempar `TypeError` (subclass `Error`, bukan `Exception`), sehingga `on Exception` tidak menangkapnya. `warmUp` di-`await` dalam `Future.wait` sebelum `runApp`; `runZonedGuarded` menangkap error tetapi `runApp` tidak pernah dipanggil.
**Dampak:** Layar kosong/startup gagal total hanya karena satu baris cache rusak.
**Perbaikan:** Root divalidasi `is Map<String, dynamic>`; setiap nilai divalidasi `is int` dan berada di `0..0xFFFFFFFF`; baris buruk dilewati. Catch terluar diubah menjadi `on Object catch`, dan handshake `getCacheVersion` juga memiliki catch `Object`.
**Verifikasi:** `warmUp` test baru mencakup root array, nilai string, nilai negatif, key non-numerik, dan baris hard-fallback.

### P-03 — Ekstraksi native dapat menggantung future (Fixed)

**Lokasi:** `lib/services/native_palette_service.dart:66-70`, `:346-350`; `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt:167`, `:415-431`.
**Akar masalah:** Watchdog native 5 detik baru dijadwalkan **setelah** `Palette.generate` selesai, jadi ekstraksi yang macet tidak pernah memicu watchdog. Tidak ada timeout di Dart. `_prefetchPalette` menahan slot prefetch selama future belum selesai.
**Dampak:** Future dan slot prefetch dapat tertahan tanpa batas; UI tetap fallback tetapi pekerjaan lain tidak maju.
**Perbaikan:** Setiap percobaan `extractPalette` dibungkus `.timeout(extractTimeout)` dengan default 8 detik (mutable untuk test) dan tetap mengikuti retry sekali. Cache-version handshake dibatasi 2 detik.
**Verifikasi:** Test timeout memakai 20 ms + dua percobaan dan memastikan fallback serta `getSync == null`; belum ada test integrasi dengan native yang benar-benar macet.

### P-04 — Prefetch palette sia-sia pada mode blur (Fixed)

**Lokasi:** `lib/services/audio/playback_manager.dart:898-907`.
**Akar masalah:** `_prefetchPalette` selalu memanggil `NativePaletteService.get`, tanpa melihat `ThemeController.playerBackgroundStyle`. Pada mode `artworkBlur`, warna palette tidak dipakai background.
**Dampak:** Decode/MMCQ dan I/O berjalan untuk hasil yang tidak terlihat, menambah tekanan pada artwork executor 3 thread yang juga dipakai cache artwork.
**Perbaikan:** Prefetch keluar lebih awal bila style `artworkBlur`. Saat pengguna kembali ke `fluid`, widget player mengekstrak on-demand (fallback tampil sementara).
**Verifikasi:** Alur style dibaca dari `ThemeController`; belum ada test playback karena `PlaybackManager` tidak memiliki suite unit.

### P-05 — Race palette pada kartu album (Fixed)

**Lokasi:** `lib/widgets/pages/home/albums_section/card.dart:52-76`.
**Akar masalah:** `_loadPaletteColor` hanya memeriksa `mounted` setelah `await`. Kartu yang didaur ulang untuk album lain dapat menimpa `_cardColor` dengan palette album lama. Warna lama juga tetap tampil selama palette album baru dimuat.
**Perbaikan:** `didUpdateWidget` mengembalikan warna ke fallback saat `coverSongId` berubah; setelah await, hasil hanya diterapkan bila `widget.album.coverSongId == songId`.
**Verifikasi:** Logika state diperiksa; belum ada widget test khusus.

### P-06 — Palette tidak mengikuti eviction artwork (Fixed)

**Lokasi:** `lib/services/artwork_repository.dart:264-276`; `lib/services/native_palette_service.dart:273-282`.
**Akar masalah:** `ArtworkRepository.evict` menghapus path/provider/disk artwork, tetapi cache palette tetap menyimpan warna dari file lama. `NativePaletteService.getSync` akan terus mengembalikannya.
**Perbaikan:** `invalidate(songId)` menghapus entri LRU, menaikkan generation, membuang future in-flight, dan menjadwalkan persistensi. Dipanggil dari `evict` sebelum delete native. Ekstraksi yang dimulai sebelum invalidasi tidak boleh menulis cache (cek generation).
**Verifikasi:** Test invalidation dan test in-flight stale completion ditambahkan.

### P-07 — Kontras teks kartu album (Fixed)

**Lokasi:** `lib/widgets/pages/home/albums_section/card.dart:150-171`; `lib/utils/palette_contrast.dart`.
**Akar masalah:** Nama album selalu putih dan artis `0xB3FFFFFF`. Koreksi neutral-dominance dapat memilih primary sangat terang (putih/abu), membuat teks tidak terbaca.
**Perbaikan:** Helper `paletteForegroundColor` / `paletteSecondaryForegroundColor` memakai luminance W3C 0.179: `black87`/`black54` pada background terang, putih/white70 pada background gelap.
**Verifikasi:** Unit test untuk warna gelap, putih, dan mid-gray ditambahkan.

### P-08 — Persistensi palette dapat bertumpuk (Fixed)

**Lokasi:** `lib/services/native_palette_service.dart:206-250`.
**Akar masalah:** Dua pemanggilan `_persist` dapat berjalan bersamaan dan menulis `$path.tmp` yang sama; rename dari writer lambat dapat memindahkan file yang sedang/baru ditulis writer lain.
**Perbaikan:** Flag `_persisting` membuat satu loop penulis; `_dirty` diperiksa ulang setelah setiap tulisan sehingga perubahan yang datang saat menulis ikut ditulis. Temp path kini hanya punya satu penulis.
**Verifikasi:** Logika loop dan `finally` diperiksa; belum ada test konkurensi filesystem.

### P-09 — Blur tidak retry saat lease null (Fixed)

**Lokasi:** `lib/widgets/player/player_background/cover_blur.dart:228-241`.
**Akar masalah:** `_requestedBlurKey` sudah di-set sebelum `ArtworkBlurCache.acquire`. Bila acquire mengembalikan null (eviction/decode race), key tidak pernah diminta ulang; background memakai runtime `ImageFilter` sepanjang track.
**Perbaikan:** Maksimal dua retry dengan jeda 600 ms; `_requestedBlurKey` direset agar build berikutnya meminta ulang. Retry direset saat sukses, ganti lagu, atau provider baru. Timer dibatalkan saat dispose.
**Verifikasi:** Lifecycle timer/request ID diperiksa; belum ada widget test cache.

### P-10 — Shader GPU tidak dilepas (Fixed)

**Lokasi:** `lib/widgets/player/player_background/artwork.dart:128-137`.
**Akar masalah:** `_painter` dan `_program` di-null-kan secara implisit saat State dibuang, tetapi `ui.FragmentShader` memegang resource native dan memiliki `dispose()`; `FragmentProgram` tidak memiliki `dispose()`.
**Perbaikan:** `dispose()` memanggil `_painter?.shader.dispose()` sebelum melepas referensi, setelah AnimationController dihentikan.
**Verifikasi:** API dan urutan dispose diperiksa; belum ada leak test perangkat.

### P-11 — Dokumentasi/memory drift (Fixed)

**Lokasi:** `.agents/memory/artwork-blur-cache.md`, `native-palette-engine.md`, `theme-assets-ui.md`, `app-init-navigation.md`, `dart-layer-map.md`, `MEMORY.md`; komentar `artwork_blur_cache.dart:39` dan `media_store_service.dart:98`.
**Akar masalah:** Memory menyebut sumber blur 384 px dan sigma 32 (kode 64 px/sigma 28), executor 2 thread (kode 3 thread), serta masih menyebut `PaletteExtractor`/`palette_extractor.dart` yang sudah dihapus.
**Perbaikan:** Nilai dan nama jalur diselaraskan dengan implementasi; referensi historis yang memang menjelaskan penghapusan tetap dipertahankan. Dokumentasi juga mencatat v9, timeout, validasi warm-up, serialisasi persist, dan invalidasi.
**Verifikasi:** Pencarian ulang `384`, `sigma 32`, `PaletteExtractor`, `two threads` pada dokumen aktif tidak menemukan drift baru.

### P-12 — Chain merge pada clustering OKLab (Fixed)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt:770-790`; `NativePaletteModels.kt:25-34`.
**Akar masalah:** Greedy matching membandingkan swatch baru dengan **semua** anggota cluster. Untuk rantai A≈B≈C dengan jarak A–C di atas threshold, B dapat menjembatani A dan C sehingga dua keluarga visual berbeda tergabung.
**Perbaikan:** Perbandingan hanya terhadap `representativeSwatch` cluster. Dokumentasi model diperbarui.
**Verifikasi:** Test E04 memakai rantai OKLab `A=0xFF3D2929`, `B=0xFF4D3333`, `C=0xFF7A5252` (dAB=0.047, dBC=0.132, dAC=0.179) dan memastikan C tetap menjadi peran accent terpisah.

### P-13 — Coverage test palette (Fixed, belum dieksekusi)

**Lokasi:** `test/services/native_palette_service_test.dart`, `test/utils/palette_contrast_test.dart`, `android/app/src/test/kotlin/dev/wndavenz/music/NativePaletteBridgeTest.kt:403-460`.
**Akar masalah:** Sebelumnya hanya ada test logging warm-up dan ThemeController; tidak ada test untuk validasi cache, timeout, invalidasi, dedup, padding, atau derivasi netral.
**Perbaikan:** Ditambahkan test Dart untuk warm-up korup/validasi/padding/dedup/timeout/hard-fallback/invalidasi dan test Kotlin E04–E06. Test belum dijalankan karena toolchain tidak tersedia.

### P-14 — Artwork netral penuh mendapat padding biru (Fixed)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt:543-560`.
**Akar masalah:** Bila tidak ada kandidat kromatik (mis. cover hitam-putih), fungsi lama memanggil `buildFallbackFromPalette`, yang mengambil named swatch seadanya lalu mengisi slot kosong dengan `FALLBACK` biru-abu. Cover netral dapat memperoleh aksen biru yang tidak ada di artwork.
**Perbaikan:** Jika kandidat kosong, swatch dengan populasi terbesar menjadi primary dan keempat peran lain diderivasi dari warna itu. Named-swatch fallback kini hanya untuk Palette kosong.
**Verifikasi:** Test E05 memastikan seluruh output dari artwork abu-abu tetap netral (R=G=B).

### P-15 — Primary netral menghasilkan hue merah (Fixed)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt:855-890`.
**Akar masalah:** `deriveHighlight`, `deriveSecondary`, `deriveAccent`, dan `deriveShadow` memaksa saturasi minimum 0.10–0.28. HSL netral memiliki hue 0; memaksa saturasi mengubah abu-abu menjadi merah muda/merah.
**Perbaikan:** Bila saturasi basis di bawah `NEUTRAL_SATURATION` (0.12), saturasi dipertahankan apa adanya; hanya lightness yang berubah. Warna kromatik tetap memakai perilaku lama.
**Verifikasi:** Test E06 memastikan highlight/shadow dari primary putih tetap netral. Perubahan algoritma menaikkan `CACHE_VERSION` ke 9 dan fallback Dart ke 9.

## Matriks prioritas

| Prioritas | Temuan | Tindakan |
|---|---|---|
| Tinggi | Tidak ada | — |
| Sedang | P-01, P-02, P-03, P-04, P-14 | Diperbaiki |
| Rendah | P-05, P-06, P-07, P-08, P-09, P-10, P-11, P-12, P-13, P-15 | Diperbaiki |
| Residual | Timeout tidak membatalkan job native; invalidasi saat job native lama masih in-flight dapat di-coalesce | Didokumentasikan sebagai risiko rendah |

## Temuan positif

- Deduplikasi palette ada di empat lapisan: `_pending` Dart, `inFlightBySongId` native, per-song lock `ArtworkCacheManager.getOrExtract`, dan `_prefetchingSongs` playback.
- Callback native memakai exactly-once `AtomicBoolean` + watchdog; `dispose()` menutup semua request yang tertunda.
- Fallback tidak dipersistensi, sehingga kegagalan transien tetap dapat di-retry.
- Pemilihan 5 peran memakai populasi, saturasi, lightness, clustering OKLab, dan koreksi neutral-dominance; bukan sekadar tiga warna pertama MMCQ.
- Blur cache membatasi frame 3 entri, memakai lease, dan menunda eviction sampai frame berikutnya.
- Shader dijalankan pada canvas 256×512 lalu di-upscale, bukan resolusi layar penuh.
- Persistensi disk memakai tulisan atomik dan nama file berversi; Dart dan native kini sama-sama v9.
- `ArtworkRepository` dan `ArtworkCacheManager` memakai direktori artwork yang sama, sehingga tidak ada pembacaan disk ganda untuk sumber yang sama.

## Verifikasi

| Pemeriksaan | Hasil |
|---|---|
| `dart format` pada seluruh berkas Dart yang diubah | Lulus; 12 berkas diperiksa, 0 berubah pada run terakhir |
| `git diff --check` | Lulus (tidak ada whitespace error) |
| `flutter analyze` | Tidak dapat dijalankan: Flutter tidak tersedia |
| `flutter test` | Tidak dapat dijalankan: Flutter tidak tersedia |
| `./gradlew testDebugUnitTest` (Kotlin E04–E06) | Tidak dapat dijalankan: Java/Gradle tidak tersedia |
| Test Dart baru | Ditulis, belum dieksekusi |
| Verifikasi perangkat (kontras, blur, warna netral) | Belum dilakukan |

**Kesimpulan verifikasi:** Perubahan lolos parsing/formatter dan pemeriksaan statis manual. Test regresi harus dijalankan melalui CI Flutter/Kotlin sebelum rilis; klaim kelulusan test tidak dibuat di sini.

## Risiko residual

1. **Job native tidak dapat dibatalkan.** Timeout Dart mengembalikan fallback dan membebaskan slot, tetapi `Palette.generate` yang benar-benar macet tetap berjalan di executor native. Retry berikutnya dapat coalesce ke job yang sama. Dampak dibatasi oleh fallback dan jumlah retry.
2. **Invalidasi saat job native lama masih berjalan.** `invalidate` membuang future Dart, tetapi native belum menerima sinyal pembatalan. Request baru dapat coalesce ke job lama dan (pada kasus artwork diganti di tempat, bukan dihapus) men-cache warna lama. Untuk eviction biasa, artwork memang dihapus sehingga hasil lama tidak berbahaya. Perbaikan penuh memerlukan token generasi di kontrak channel native.
3. **Persistensi invalidasi bersifat debounced.** Cache disk dihapus pada tulisan berikutnya (800 ms). Proses yang dibunuh sebelum tulisan selesai dapat menyisakan entri lama di disk; entri itu akan dibaca saat warm-up berikutnya.
4. **Belum ada validasi perangkat.** Perubahan warna netral dan kontras kartu perlu dilihat pada beberapa artwork nyata (putih, hitam, abu, warna ekstrem) dan pada mode gelap/terang.
5. **Lint/analyzer belum dijalankan.** Meskipun aturan `avoid_catches_without_on_clauses`, `discarded_futures`, dan strict-casts sudah dipertimbangkan, hanya `dart analyze` dengan resolusi paket Flutter yang dapat memastikan bersih.

## Berkas yang berubah

**Dart**
- `lib/services/native_palette_service.dart`
- `lib/services/artwork_repository.dart`
- `lib/services/audio/playback_manager.dart`
- `lib/services/artwork_blur_cache.dart`
- `lib/services/media_store_service.dart`
- `lib/widgets/player/player_background/cover_blur.dart`
- `lib/widgets/player/player_background/artwork.dart`
- `lib/widgets/pages/home_sections.dart`
- `lib/widgets/pages/home/albums_section/card.dart`
- `lib/utils/palette_contrast.dart` (baru)

**Kotlin**
- `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteBridge.kt`
- `android/app/src/main/kotlin/dev/wndavenz/music/NativePaletteModels.kt`
- `android/app/src/test/kotlin/dev/wndavenz/music/NativePaletteBridgeTest.kt`

**Test Dart**
- `test/services/native_palette_service_test.dart` (baru)
- `test/utils/palette_contrast_test.dart` (baru)

**Dokumentasi/memory**
- `docs/ARCHITECTURE_TREE.md`
- `.agents/memory/MEMORY.md`
- `.agents/memory/artwork-blur-cache.md`
- `.agents/memory/native-palette-engine.md`
- `.agents/memory/theme-assets-ui.md`
- `.agents/memory/app-init-navigation.md`
- `.agents/memory/dart-layer-map.md`
