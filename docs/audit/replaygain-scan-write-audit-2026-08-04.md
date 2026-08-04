# Audit ReplayGain Scan dan Write

**Tanggal:** 2026-08-04  
**Scope:** seluruh jalur scan, perhitungan loudness, cache hasil scan, permission
MediaStore, penulisan tag permanen, verifikasi, rollback, dan penghapusan tag
ReplayGain.  
**Target perangkat:** Xiaomi Mi 9T/K20, Android 11 / MIUI 12.

## Ringkasan

Arsitektur utama sudah tersambung dengan benar:

```text
Flutter Settings
  -> ReplayGainService.scanLibrary()
  -> MethodChannel scanTrack
  -> MainActivity.replayGainScanExecutor
  -> PcmDecoder + MediaCodec
  -> libebur128 melalui JNI
  -> cache MetadataCacheDb / SharedPreferences
  -> MethodChannel writeReplayGain
  -> MediaStoreWriteGate
  -> fd-based TagLib writer
  -> close -> reopen -> verify
```

Temuan prioritas:

| ID | Severity | Status | Ringkasan |
|---|---|---|---|
| RG-01 | **HIGH** | Diperbaiki | Semua error setelah backup mencoba restore; hasil restore diverifikasi dan kegagalan dikembalikan sebagai `ROLLBACK_FAILED`. |
| RG-02 | **MEDIUM** | Diperbaiki | Track-only menghapus field album ReplayGain/R128 lama; verifikasi juga memastikan field tersebut tidak tersisa. |
| RG-03 | **MEDIUM** | Diperbaiki | Format angka Kotlin memakai `Locale.ROOT`, dan parser Dart menolak angka locale/malformed yang terpotong. |
| RG-04 | **MEDIUM** | Diperbaiki | Penyimpanan peak menghapus key lama ketika hasil baru tidak memiliki peak. |
| RG-05 | **MEDIUM** | Diperbaiki | Nilai write divalidasi finite, peak non-negatif, dan field album harus lengkap atau seluruhnya kosong di Dart/Kotlin/native. |
| RG-06 | **MEDIUM** | Diperbaiki | Path dan `songId` dicocokkan melalui canonical path sebelum write/remove. |
| RG-07 | **MEDIUM** | Diperbaiki | Scanner menolak sample rate/channel count yang hilang atau di luar rentang, tanpa fallback. |
| RG-08 | **MEDIUM** | Mitigasi | Backup region tetap mencakup seluruh metadata dan dipakai untuk rollback; verifikasi sukses masih membandingkan field yang diketahui plus sentinel, bukan byte metadata penuh. |
| RG-09 | **MEDIUM** | Diperbaiki | Scan/cache/write terikat path, ukuran, dan mtime; file yang berubah ditolak sebagai stale. |
| RG-10 | **LOW** | Gap | Tidak ada test native end-to-end untuk scan, TagLib write, verification, dan restore. |
| RG-11 | **LOW** | Gap yang sudah didokumentasikan | Cancellation hanya menghentikan batch setelah lagu berjalan selesai; native decoder tidak dapat dibatalkan di tengah lagu. |

Build APK release berhasil setelah remediasi. Test Dart penuh belum dapat dimulai
karena hook `native_audio_runtime` pada host runner tidak menemukan compiler
Linux; jalur APK memakai toolchain Android dan tetap berhasil.

### Status remediasi

Perbaikan diterapkan pada jalur Kotlin/JNI/native dan Flutter. Scan library kini
bersifat scan-only; penulisan tag permanen harus berasal dari aksi write
eksplisit. Executor write dibuat serial untuk mencegah dua operasi TagLib
menyentuh region file yang sama. RG-08 sengaja tetap ditandai mitigasi karena
verifikasi penuh seluruh metadata memerlukan representasi/canonicalizer metadata
lintas empat format, sedangkan backup exact-region sudah menjadi batas pemulihan
yang aman.

---

## Temuan detail

### RG-01 — Jalur gagal setelah backup tidak selalu melakukan rollback

**Severity:** HIGH  
**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:209-243`
- `android/app/src/main/cpp/replaygain/tag_writer.cpp:254-326`

`WriteReplayGainTagsFd()` mengambil `RegionBackup` sebelum memanggil
`TagLib::File::save()`. Namun `ReplayGainBridge.runFdMutation()` hanya memakai
backup tersebut ketika:

1. native write mengembalikan `NONE`, dan
2. langkah reopen + verification mengembalikan error.

Jika `file.save()` mengembalikan `kWriteFailure`, bridge langsung melakukan
`return outcome.error` pada baris 215. Tidak ada usaha restore. Hal yang sama
terjadi bila file sudah berhasil dimutasi tetapi `openFd(songId)` untuk fd
verifikasi gagal pada baris 217-219: fungsi mengembalikan
`WRITE_ACCESS_DENIED` tanpa restore.

`TagLib::save()` biasanya mengembalikan false sebelum menghasilkan kerusakan,
tetapi kontrak API saat ini tidak membuktikan itu. Dari sisi safety, setelah
mutasi dimulai, file harus dianggap mungkin sudah berubah sebagian sampai
dibuktikan sebaliknya.

**Dampak:**

- write dilaporkan gagal, tetapi metadata baru atau metadata parsial bisa sudah
  berada di file;
- file tidak otomatis dikembalikan ke `RegionBackup`;
- komentar dan dokumentasi saat ini memberi kesan semua failure setelah write
  akan di-rollback, padahal tidak demikian.

**Rekomendasi:**

- bedakan failure sebelum mutasi dan failure setelah `save()` mulai berjalan;
- untuk setiap failure setelah backup dibuat, coba buka fd baru dan jalankan
  `RestoreMetadataRegionFd`;
- jika reopen restore juga gagal, kembalikan error khusus seperti
  `ROLLBACK_FAILED`, bukan hanya `VERIFICATION_FAILED`;
- verifikasi harus tetap dijalankan bila write mengklaim sukses;
- tambahkan log yang menyatakan apakah rollback berhasil, gagal, atau tidak
  dapat dicoba.

---

### RG-02 — Write track-only tidak menghapus album tag lama

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/cpp/replaygain/tag_writer.cpp:152-168`
- `android/app/src/main/cpp/replaygain/tag_writer.cpp:274-320`
- `lib/services/replay_gain_service/service.dart:321-327`

`ApplyReplayGainFields()` hanya menulis album fields jika `req.has_album` true.
Jalur MP3 juga hanya memanggil `SetTxxx()` untuk album fields bila
`req.has_album` true. Tidak ada `Remove...` untuk album fields ketika request
track-only.

Akibatnya, urutan berikut meninggalkan data lama:

1. scan album dan tulis `REPLAYGAIN_ALBUM_*` serta `R128_ALBUM_GAIN`;
2. scan satu track dan tulis track-only;
3. tag album lama tetap berada di file.

`scanOneSong()` memang mengirim write track-only. Playback mode album dapat
kemudian membaca album gain yang berasal dari pengukuran album sebelumnya,
walaupun file baru saja diberi track measurement yang berbeda.

**Rekomendasi:**

- tetapkan kontrak eksplisit:
  - request tanpa album fields berarti “hapus album fields lama”, atau
  - request tanpa album fields berarti “pertahankan album fields”;
- untuk fitur scan track/library saat ini, pilihan yang paling aman adalah
  menghapus album fields lama jika album measurement tidak ikut dikirim;
- terapkan aturan yang sama untuk `REPLAYGAIN_ALBUM_GAIN`,
  `REPLAYGAIN_ALBUM_PEAK`, dan `R128_ALBUM_GAIN`;
- tambahkan test rescan album -> track-only -> assert album fields tidak stale.

---

### RG-03 — Cache Kotlin sensitif terhadap locale perangkat

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:45-46`
- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:85-88`
- `lib/services/replay_gain_service/service.dart:190-197`

Bridge Kotlin memakai:

```kotlin
"%+.2f dB".format(result.recommendedGainDb)
"%.6f".format(dbToLinear(result.samplePeakDbfs))
```

`String.format`/`format` tanpa `Locale.ROOT` menggunakan locale default
perangkat. Pada locale yang memakai koma desimal, cache dapat menyimpan
`+1,23 dB`.

Parser Dart `_parseGainDb()` hanya mengenali titik sebagai pemisah desimal.
Dengan string `+1,23 dB`, regex dapat membaca `+1` saja sehingga gain yang
dipakai playback salah.

Tag writer C++ memakai `snprintf` dan tidak mengikuti locale aplikasi, sehingga
tag file dan cache SQLite bisa memiliki representasi berbeda.

**Rekomendasi:**

- gunakan `Locale.ROOT` untuk seluruh formatting numerik cache:

```kotlin
String.format(Locale.ROOT, "%+.2f dB", gain)
String.format(Locale.ROOT, "%.6f", peak)
```

- tambahkan regression test pada locale `id_ID` atau locale koma;
- sebaiknya parser Dart juga menolak nilai ambigu, bukan mengambil angka parsial.

---

### RG-04 — Peak lama di SharedPreferences tidak dihapus

**Severity:** MEDIUM  
**Lokasi:** `lib/services/replay_gain_service/service.dart:262-273`

`_saveToPrefs()` hanya memanggil `setString('rg_<id>_peak', ...)` bila
`data.peakLinear != null`. Jika hasil baru tidak memiliki peak, key peak lama
tetap tersimpan.

Skenario:

1. scan pertama menyimpan gain dan peak;
2. scan berikutnya menghasilkan gain valid tetapi peak null/invalid;
3. `_cache` saat ini benar-benar memiliki `peakLinear == null`;
4. setelah restart, `_loadFromPrefs()` membaca gain baru tetapi peak lama.

Clipping protection kemudian dapat menggunakan peak dari pengukuran berbeda.

**Rekomendasi:**

- panggil `prefs.remove('rg_<id>_peak')` ketika peak null;
- lakukan hal yang sama untuk field cache lain yang opsional;
- tambahkan test persistence: save-with-peak lalu save-without-peak lalu load.

---

### RG-05 — Nilai write dari MethodChannel tidak divalidasi

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:131-147`
- `android/app/src/main/cpp/replaygain/replaygain_jni.cpp:88-103`
- `android/app/src/main/cpp/replaygain/tag_writer.cpp:37-49`

Bridge memeriksa keberadaan dan tipe numerik, tetapi tidak memeriksa:

- `isFinite()` untuk gain, peak, dan LUFS;
- peak tidak negatif;
- nilai berada pada range operasional yang masuk akal;
- album fields konsisten: gain, peak, dan integrated LUFS harus hadir bersama.

Nilai `NaN`/infinity atau nilai ekstrem dapat masuk ke formatter. `FormatPeak`
memiliki perlindungan parsial, tetapi `FormatGainDb()` dapat menulis representasi
non-numerik seperti `nan dB`. Nilai LUFS non-finite juga menyebabkan konversi
R128 fallback ke 0, sehingga tag track gain dan R128 dapat tidak konsisten.

**Rekomendasi:**

- validasi semua input di Kotlin sebelum JNI;
- ulangi validasi defensif di C++ sebelum format dan write;
- kembalikan `kInvalidArgument` untuk nilai non-finite atau kombinasi album
  yang tidak lengkap;
- gunakan batas domain yang terdokumentasi, bukan clamp diam-diam untuk input
  hasil scan.

---

### RG-06 — `path` menentukan format, `songId` menentukan file

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:131-147`
- `android/app/src/main/kotlin/dev/wndavenz/music/MainActivity.kt:923-941`
- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainModels.kt:81-89`

Saat write:

- `TagFormat.fromPath(path)` menentukan apakah native memakai parser MP3, FLAC,
  Ogg Vorbis, atau Opus;
- `openReplayGainWriteFd(songId)` membuka URI MediaStore berdasarkan `songId`.

Tidak ada validasi bahwa `path` dan `songId` masih menunjuk file yang sama,
atau bahwa extension path cocok dengan file aktual. Song object normal biasanya
konsisten, tetapi file dapat dipindah/diubah/direscan antara scan dan write.

**Dampak:**

- parser format yang salah dapat menghasilkan `CORRUPTED_FILE` atau
  `UNSUPPORTED_FORMAT`;
- pada kombinasi yang kebetulan terlihat valid, metadata bisa ditulis dengan
  asumsi format yang salah;
- cache path yang diinvalidate bisa berbeda dari file yang benar-benar ditulis.

**Rekomendasi:**

- resolve `songId` ke path/display name aktual di sisi Android dan gunakan hasil
  itu sebagai sumber format;
- atau kirim dan validasi fingerprint `(songId, canonicalPath, size, mtime)`
  dari hasil scan;
- jangan menjadikan extension dari input Dart sebagai satu-satunya penentu
  format write.

---

### RG-07 — Fallback format decoder dapat menghasilkan pengukuran salah

**Severity:** MEDIUM  
**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/PcmDecoder.kt:63-70`

Jika `MediaFormat.KEY_SAMPLE_RATE` atau `KEY_CHANNEL_COUNT` tidak tersedia,
decoder menggunakan default `44100 Hz` dan `2 channel`. Untuk playback biasa,
fallback ini mungkin membantu melewati file yang metadata formatnya tidak
lengkap. Untuk scan yang hasilnya dapat ditanam permanen, fallback tersebut
berisiko:

- sample rate yang salah memengaruhi filter/K-weighting libebur128;
- jumlah channel yang salah mengubah interpretasi interleaved PCM;
- hasil gain yang salah kemudian dianggap valid dan ditulis ke file.

**Rekomendasi:**

- untuk ReplayGain scan, perlakukan sample rate/channel count yang hilang atau
  invalid sebagai decode failure;
- hanya gunakan fallback bila MediaCodec memberi bukti kuat bahwa format PCM
  aktual cocok;
- tambahkan log format aktual sebelum analyzer dibuat.

---

### RG-08 — Verification tidak mencakup seluruh metadata yang diklaim dipreservasi

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/cpp/replaygain/tag_writer.h:62-76`
- `android/app/src/main/cpp/replaygain/tag_writer.cpp:476-500`

Post-write verification memeriksa:

- track gain/peak;
- album gain/peak jika dikirim;
- R128 untuk Opus;
- title, artist, dan album sebagai sentinel.

Dokumentasi mengeklaim cover art, lyrics, ISRC, disc/track number, comments,
album artist, dan metadata lain tetap utuh, tetapi field-field tersebut tidak
dibaca ulang dan tidak dibandingkan. Jika TagLib atau provider file mengubah
metadata lain tanpa mengubah tiga sentinel, verification tetap melaporkan
sukses.

`RegionBackup` tersedia, tetapi hanya dipakai saat verification gagal; backup
tersebut bukan bukti bahwa metadata lain tetap sama.

**Rekomendasi:**

- untuk format yang didukung, verifikasi hash/byte metadata region dengan
  normalisasi terhadap field ReplayGain yang memang diubah;
- minimal tambahkan snapshot sentinel untuk artwork length/hash, lyrics,
  comment, track/disc, dan album artist;
- dokumentasikan dengan jelas bahwa “preserve” adalah asumsi TagLib bila
  verifikasi penuh belum diimplementasikan.

---

### RG-09 — Tidak ada guard terhadap file berubah antara scan dan write

**Severity:** MEDIUM  
**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainBridge.kt:36-110`
- `lib/services/replay_gain_service/service.dart:299-329`

Scan mengukur file berdasarkan path. Write berikutnya membuka file berdasarkan
song ID, tetapi tidak membawa atau memeriksa ukuran, mtime, atau fingerprint
audio yang diukur.

File dapat berubah karena:

- editor tag lain;
- sinkronisasi/cloud;
- operasi rename/replace dari aplikasi lain;
- file dihapus lalu MediaStore ID dipakai ulang;
- proses scan yang lama beradu dengan perubahan library.

Dalam kasus ini, write masih dapat sukses dan menanam hasil pengukuran audio
lama ke file audio baru.

**Rekomendasi:**

- simpan `(size, mtime)` sebelum scan dan cek lagi sebelum write;
- untuk operasi dengan risiko tinggi, gunakan fingerprint parsial atau hash
  audio;
- jika berubah, abort dengan `STALE_SCAN` dan minta scan ulang.

---

## Hal yang sudah baik / temuan lama yang sudah terselesaikan

### Scoped Storage dan permission

Jalur aktif memakai `MediaStore` URI + `ParcelFileDescriptor.detachFd()`.
`MediaStoreWriteGate` menserialisasi dialog permission dan menggunakan
`createWriteRequest()` pada Android 11+. Tidak terlihat penggunaan raw path untuk
write file yang tidak dimiliki aplikasi.

### Kepemilikan fd

Jalur fd aktif konsisten mendokumentasikan bahwa ownership berpindah ke native
setelah `detachFd()`. `TagLib::FileStream` menutup fd ketika berhasil
`fdopen()`. Path `!stream.isOpen()` sekarang memanggil `::close(fd)` secara
eksplisit pada:

- `WriteReplayGainTagsFd`;
- `RemoveReplayGainTagsFd`;
- `ReadBackFd`;
- `RestoreMetadataRegionFd`.

Temuan fd leak dari laporan `docs/Audit_ReplayGain_WriteTag.md` adalah temuan
historis dan tidak lagi cocok dengan kode saat ini.

### Backup region dan batas alokasi

`metadata_region.cpp` sudah:

- membaca region melalui `pread`;
- menolak struktur metadata yang tidak dapat ditentukan dengan aman;
- membatasi backup pada 64 MiB sebelum `resize`;
- mendukung ID3v2, FLAC, Ogg Vorbis, dan Ogg Opus.

Temuan OOM pada laporan native lama sudah diperbaiki di kode sekarang.

### Analyzer lifecycle

`EburTrackSession` menutup handle native melalui `use`/`close`, dan album scan
mempertahankan semua session sampai `nativeComputeAlbumLoudness()` selesai.
Registry native dilindungi mutex. Tidak ditemukan kebocoran handle analyzer pada
alur normal.

### Format tag

Format dasar yang ditulis saat ini konsisten:

- MP3: ID3v2 TXXX;
- FLAC/Ogg Vorbis: Vorbis/Xiph comment;
- Ogg Opus: ReplayGain fields dan R128 Q7.8.

M4A/AAC sengaja read-only karena MP4 writer TagLib dinonaktifkan.

### Idempotensi

TXXX lama dihapus sebelum field baru ditambahkan, dan Xiph comment memakai
replace. Re-scan tidak mengakumulasi duplicate track fields dalam format yang
ditangani.

---

## Test coverage

Yang ada:

- test JVM untuk parser `TagBuilder`, termasuk field ReplayGain/R128;
- test Dart untuk model `LoudnessData`;
- release APK build berhasil setelah remediasi.

Yang belum ada:

- test native `EburAnalyzer` dengan fixture PCM;
- test album loudness dan partial-failure;
- test TagLib write/read-back untuk MP3, FLAC, Ogg Vorbis, dan Opus;
- test metadata region malformed/truncated/oversized;
- test verification failure + exact restore;
- test MediaStore fd ownership;
- test locale koma;
- test stale album fields;
- test write failure setelah `save()` mulai berjalan.

Pada host Replit, `flutter test test` belum dapat dimulai karena hook
`native_audio_runtime` tidak menemukan compiler Linux. Ini adalah keterbatasan
toolchain host; build APK Android menggunakan NDK dan berhasil.

## Prioritas tindak lanjut

1. Tambahkan test native end-to-end untuk RG-10 setelah toolchain host tersedia.
2. Pertimbangkan verifikasi canonical seluruh metadata untuk menutup sisa
   mitigasi RG-08.
3. RG-11 tetap merupakan batas cancellation native yang sudah didokumentasikan.
