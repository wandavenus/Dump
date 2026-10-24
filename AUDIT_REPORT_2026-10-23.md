# Audit Menyeluruh Repository `musicplayer`

**Tanggal:** 23 Oktober 2026  
**Versi aplikasi:** 1.5.41 (`pubspec.yaml:4`)  
**Commit saat audit:** `b931207`  
**Cakupan:** seluruh isi repository (Dart/Flutter, Kotlin/Android, C/NEON, JNI/FFI, build config, CI, dokumentasi)  
**Status:** audit saja — **tidak ada kode yang diubah**

---

## 0. Metodologi dan batasan

Audit dijalankan atas kode dan konfigurasi aktual, bukan asumsi. Alur eksekusi ditelusuri dari
`lib/main.dart` → `AudioService` / `PlaybackManager` → `Media3PlaybackBridge` →
`Media3PlaybackService.kt` → `NativeDspAudioProcessor` / JNI → C DSP, termasuk interaksi
antar-komponen (startup, service Android, channel, native runtime).

Sub-agent audit kode tidak tersedia di lingkungan ini (hanya agen riset web), sehingga 9 workstream
audit dijalankan secara paralel mandiri, ditambah 3 workstream riset eksternal:

1. Advisory keamanan untuk dependensi yang di-pin.
2. Kebijakan Google Play 2026 (target API, foreground service, izin media).
3. Implikasi lisensi GPLv3 pada distribusi APK.

### Automated checks yang dijalankan

| Pemeriksaan | Perintah | Hasil |
|---|---|---|
| Analisis Dart | `dart analyze lib test` | **No issues found** (strict-casts, strict-inference, strict-raw-types, 74 lint) |
| Test Flutter | `flutter test` | **270 test lulus** |
| Test native C/FFI | `cd native_audio_runtime && dart test` | **65 test lulus** |
| Analisis paket native | `cd native_audio_runtime && dart analyze` | **No issues found** |
| Coverage | `flutter test --coverage` | **3.065 / 14.107 baris = 21,7%** (batas atas) |
| Test Kotlin | `cd android && ./gradlew :app:testDebugUnitTest` | **Tidak dapat dijalankan**: NDK `28.2.13676358` tidak memiliki `source.properties` (kerusakan instalasi SDK di environment, bukan bug repo) |

### Skala repository

| Bahasa | File | LOC |
|---|---:|---:|
| Dart | 334 | 47.293 |
| Kotlin/Java | 78 | 24.413 |
| C/header/asm | 57 | 9.989 |

---

## 1. Executive summary

Repository ini **jauh lebih rapi dari rata-rata proyek Flutter**: analyzer bersih dengan mode ketat,
270 test Flutter + 65 test native lulus, jalur audio native bebas alokasi/lock dengan atomics dan
desain fail-open, JNI memiliki pemeriksaan kapasitas buffer, tidak ada secret ter-commit, dan
pemisahan layer Dart → bridge → Media3 → C konsisten.

Namun **belum siap produksi untuk distribusi publik**, dan penyebab utamanya bukan kualitas kode
harian:

1. **Blocker hukum (Critical):** APK mendistribusikan decoder FFmpeg berlisensi **GPLv3** di dalam
   aplikasi berlisensi **"All Rights Reserved"**, sambil *membuang* file `META-INF/LICENSE/NOTICE`
   milik dependensi Apache/LGPL.
2. **Blind spot operasional (High):** logging mati secara default di Dart, Kotlin, dan Media3
   sekaligus; error handler global mengarah ke logger yang langsung `return`; tidak ada crash
   reporting; simbol obfuscation tidak diunggah. Di lapangan, kegagalan akan **tak terlihat dan tak
   terdokumentasi**.
3. **Celah pengujian pada inti produk (High):** jalur playback yang paling kritikal justru paling
   tidak teruji — `services/audio` 2,1%, `audio_service` 0,8%, `MediaStore` 14,4%,
   `ReplayGain` 8,4%, `song_metadata` 0%; 45 dari 57 kelas Kotlin tidak punya test berpasangan.
4. **Tidak ada gate regresi (Medium):** seluruh 8 workflow hanya `workflow_dispatch`; Android lint
   `abortOnError=false` dengan baseline kosong; tidak ada ambang coverage.

Untuk pemakaian pribadi di satu perangkat (Xiaomi Mi 9T / Android 11) aplikasi ini relatif stabil.
Untuk dibagikan sebagai APK/Play Store, statusnya: **belum layak sampai P0 dan P1 pada roadmap
selesai.**

---

## 2. Temuan berdasarkan tingkat keparahan

### 2.1 CRITICAL

#### C1. Decoder FFmpeg GPLv3 di dalam aplikasi proprietary "All Rights Reserved"

- **Bukti:**
  - `android/app/build.gradle:41-46` — komentar eksplisit: *"License: GPL v3"*.
  - `android/app/build.gradle:179` — `org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1`.
  - `LICENSE:1-5` — "All Rights Reserved", melarang redistribusi.
  - Maven Central mengonfirmasi artefak berlisensi **GPL-3.0**.
  - `.github/workflows/android.yml:147-155` mengunggah APK ke GitHub Release → ada distribusi.
- **Dampak:** GPLv3 mewajibkan Corresponding Source untuk combined work dan melarang pembatasan
  tambahan. Menyebarkan APK saat ini berisiko tuntutan/takedown; "All Rights Reserved" tidak dapat
  diberlakukan pada karya gabungan tersebut. Berlaku juga untuk FFmpeg GPL — halaman legal FFmpeg
  menyatakan komponen GPL membuat seluruh FFmpeg GPL.
- **Rekomendasi:** putuskan salah satu:
  - (a) hapus decoder dan andalkan decoder platform/Media3,
  - (b) ganti ke build LGPL + wrapper berlisensi sesuai,
  - (c) relisensikan aplikasi sebagai GPLv3 dan sediakan source.

  Opsi "beli lisensi komersial FFmpeg" praktis tidak tersedia. Wajib review hukum sebelum rilis.
- **Status:** terkonfirmasi dari konfigurasi + metadata artefak (bukan opini runtime).
- **Update 2026-10-24:** rekomendasi **(b) diterapkan** — decoder kini dibangun
  lokal dari FFmpeg `n8.1.3` dengan `--disable-gpl --disable-nonfree
  --disable-version3` (LGPL-2.1-or-later) lewat `android/decoder-ffmpeg/` +
  `android/build-ffmpeg-jni.sh`; AAR Jellyfin dihapus. Temuan di atas
  dipertahankan sebagai catatan historis.

#### C2. Notis lisensi pihak ketiga dibuang dari APK

- **Bukti:** `android/app/build.gradle:116-123` mengecualikan `META-INF/LICENSE*`,
  `META-INF/NOTICE*`, `META-INF/DEPENDENCIES`, `META-INF/LGPL2.1`.
- **Dampak:** Media3/AndroidX (Apache-2.0 §4) mewajibkan retensi NOTICE; komponen LGPL/TagLib juga
  punya kewajiban notis. Ini memperparah C1 dan dapat memicu keluhan kepatuhan.
- **Rekomendasi:** pertahankan NOTICE/LICENSE, tambahkan layar "Open-source licenses"
  (`LicenseRegistry` pada Flutter).
- **Status:** terkonfirmasi.

### 2.2 HIGH

#### H1. Diagnostik produksi praktis nol (kegagalan senyap)

- **Bukti:**
  - `lib/services/log_service/service.dart:12` — `loggingEnabled = ValueNotifier(false)`.
  - `lib/services/log_service/service.dart:29` — default prefs `false`.
  - `lib/services/log_service/service.dart:90-91` — `if (!loggingEnabled.value) return;`.
  - `lib/main/main.dart:100-116` — `FlutterError.onError` dan `PlatformDispatcher.onError`
    mengarah ke `LogService` (no-op saat logging mati), lalu `return true` (menelan error).
  - `android/.../events/EventEmitter.kt:99-120` — Logcat mati **dan**
    `Media3 Log.LOG_LEVEL_OFF`.
  - Tidak ada dependensi Crashlytics/Sentry di `pubspec.yaml`.
  - `.github/workflows/android.yml:132` memakai `--split-debug-info`, tetapi `:147-155` hanya
    mengunggah APK — simbol dibuang.
- **Dampak:** crash/ANR/desync di perangkat pengguna tidak menghasilkan jejak apa pun; stack trace
  build ter-obfuscate tidak bisa di-symbolicate.
- **Rekomendasi:** logger selalu merekam ERROR ke buffer/file persisten meski toggle mati; tambahkan
  crash reporter; unggah `build/debug-info` + `mapping.txt` sebagai artefak rilis; tambahkan test
  bahwa error handler benar-benar menulis.
- **Status:** terkonfirmasi statis.

#### H2. Jalur playback inti hampir tidak teruji

- **Bukti coverage per area:**

  | Area | Coverage |
  |---|---:|
  | `services/audio` | **2,1%** (21/986) |
  | `services/audio_service` | **0,8%** (4/504) |
  | `services/media_store_service.dart` | **14,4%** |
  | `replay_gain_service` | **8,4%** |
  | `song_metadata_service` | **0%** |
  | `media_capabilities_service` | **0%** |
  | `services/automix_service` | 69,6% |

  - 18 kelas test Kotlin untuk 57 file main; **45 tanpa pasangan**, termasuk
    `Media3PlaybackService`, `AudioOffloadManager`, `PlaybackNotificationManager`,
    `SleepTimerManager`, `PreloadManager`, `AudioEffectsManager`.
- **Dampak:** `AudioService.playSongAt` (rollback queue, `_isLoading`), crossfade, offload,
  notifikasi, dan ReplayGain adalah area paling berisiko regresi namun tidak dijaga test.
- **Rekomendasi:** target minimum 60% untuk `services/audio_service`,
  `services/media_store_service`, `replay_gain_service`; tambah test Kotlin untuk
  `SleepTimerManager`, `PlaybackNotificationManager`, `AudioOffloadManager`; jalankan di CI push/PR.
- **Status:** terkonfirmasi (angka coverage).

### 2.3 MEDIUM

#### M1. `MediaSessionService` diekspor tanpa penyaringan controller + menerima `ACTION_PLAY_URI` dari aplikasi mana pun

- **Bukti:**
  - `AndroidManifest.xml:77-79` — `android:exported="true"`.
  - `Media3PlaybackService.kt:1072` — `onGetSession(...) = session` tanpa override `onConnect`
    (grep: tidak ada `onConnect` di seluruh sumber Kotlin).
  - `Media3PlaybackService.kt:1114-1133` — memproses `ACTION_PLAY_URI` untuk `file://`,
    `content://`, atau path apa pun tanpa `://`.
- **Dampak:** aplikasi lain dapat terhubung sebagai `MediaController`, mengontrol playback/membaca
  metadata, dan memicu pemutaran path yang dapat dibaca aplikasi kita (termasuk file privat). Bukan
  eskalasi data langsung, tetapi pelanggaran batas kepercayaan.
- **Rekomendasi:** override `onConnect` dengan allowlist paket/system + batasi `SessionCommands`;
  lindungi aksi kustom dengan permission `signature`; validasi URI.
- **Status:** terkonfirmasi statis; eksploitabilitas penuh perlu uji perangkat.

#### M2. `READ_MEDIA_IMAGES` (akses foto luas) hanya untuk menyimpan gambar QR

- **Bukti:** `AndroidManifest.xml:16`; satu-satunya pemakaian galeri adalah
  `lib/pages/settings_page/about.dart:110-153` (`Gal.hasAccess/requestAccess/putImage` untuk QR
  donasi).
- **Dampak:** melanggar least-privilege; kebijakan Photo & Video Permissions Google Play berlaku
  untuk `READ_MEDIA_IMAGES` dan meminta akses luas hanya bila merupakan fungsi inti.
- **Rekomendasi:** simpan QR lewat MediaStore `insert` tanpa izin baca, atau gunakan
  `Gal.putImageBytes` dengan izin minimal; hapus `READ_MEDIA_IMAGES` bila tidak perlu.
- **Status:** terkonfirmasi untuk manifest; relevansi Play hanya jika didistribusikan via Play.

#### M3. Cold start memblokir frame pertama pada dialog izin + I/O + prewarm

- **Bukti:** `lib/main/main.dart:33` (`await _requestAudioPermission()` — menunggu interaksi user),
  `:36-97` (`Future.wait` warmup + 3× prewarm 3 detik + 3× prewarm 2 detik), `:119-133`
  (`await PlaybackManager.initialize`, `DeviceDsp.initialize`, `AudioEffectsService.init`,
  `AutomixService.loadSettings`, `MediaCapabilitiesService.initialize`, lalu `runApp`).
- **Dampak:** `runApp` baru dipanggil setelah izin diputuskan dan seluruh inisialisasi selesai; di
  instalasi baru ini bisa berarti layar launch beberapa detik. Tidak ada timeout/fallback per
  langkah — satu langkah yang menggantung/melempar membuat `runApp` tak pernah tercapai (dan karena
  H1, tanpa jejak).
- **Rekomendasi:** panggil `runApp` lebih awal dengan gate izin di dalam UI; bungkus tiap
  inisialisasi dengan timeout + degradasi; ukur time-to-first-frame di perangkat.
- **Status:** terkonfirmasi dari urutan eksekusi; durasi aktual perlu pengukuran.

#### M4. Izin ditolak → library kosong tanpa penjelasan atau jalan pemulihan

- **Bukti:** `lib/main/main.dart:152-159` memanggil `Permission.storage/audio.request()` dan
  **mengabaikan status**; `lib/pages/music_list/state.dart:71-93` hanya menampilkan `noLocalSongs`;
  tidak ada `openAppSettings` di seluruh `lib/`; satu-satunya pesan penolakan izin adalah untuk
  galeri QR (`lib/l10n/app_en.arb:246`).
- **Dampak:** pengguna menolak sekali → aplikasi tampak "rusak/kosong" permanen tanpa cara
  memperbaiki.
- **Rekomendasi:** simpan status izin, tampilkan empty-state khusus dengan tombol "Buka Pengaturan",
  dan retry setelah resume.
- **Status:** terkonfirmasi.

#### M5. Tidak ada gate regresi otomatis

- **Bukti:** 8/8 workflow hanya `workflow_dispatch` (`ci.yml:3-4`, `flutter-check.yml:3-4`,
  `kotlin-tests.yml:3-4`, `android.yml:4`, `codeql.yml`, `pages.yml`, dll.); tiga workflow
  menjalankan analyze/test yang tumpang tindih; `ci.yml` memakai
  `--no-fatal-warnings --no-fatal-infos`; `android/app/build.gradle:61` `abortOnError = false`
  dengan `lint-baseline.xml` kosong; tidak ada coverage threshold.
- **Dampak:** perubahan bisa masuk tanpa pernah dianalisis/diuji; Android lint tidak pernah menahan
  apa pun.
- **Rekomendasi:** trigger `push`/`pull_request` ke `main`; satukan workflow; aktifkan
  `abortOnError=true` + baseline nyata; tambah `--coverage` + ambang.
- **Status:** terkonfirmasi.

#### M6. Version skew Media3 dan bypass AGP yang rapuh

- **Bukti:** `android/app/build.gradle:47` (`media3_version = "1.11.1"`) vs `:179` (AAR decoder
  dibangun di Media3 **1.9.0**, transitive deps di-exclude); `android/gradle.properties` memaksa
  `android.newDsl=false` + `android.builtInKotlin=false` dan
  `kotlin.jvm.target.validation.mode=warning`.
- **Dampak:** `FfmpegAudioRenderer` (API `@UnstableApi`) berjalan di atas runtime 1.11.1 — risiko
  `NoSuchMethodError`/perilaku decode berbeda hanya muncul di rilis. Bypass AGP akan patah saat
  upgrade Flutter/AGP.
- **Rekomendasi:** uji rilis dengan file ALAC/format yang memaksa jalur FFmpeg; pertimbangkan
  decoder yang selaras versi; beri test instrumentasi untuk load `libffmpegJNI.so`.
- **Status:** potensial, butuh verifikasi runtime.

#### M7. Utang arsitektur: kelas raksasa dan 157 `part` directive

- **Bukti:** `Media3PlaybackService.kt` 2.726 baris, `MainActivity.kt` 1.714,
  `CrossfadeController.kt` 1.213, `automix_service/engine.dart` 2.580,
  `automix_service/service.dart` 2.369, `AudioService` 1.181, `PlaybackManager` 924;
  `settings_page.dart` hanya 62 baris tetapi menampung **25 part**.
- **Dampak:** perubahan kecil menyebar ke banyak file; `part` membuat semuanya satu library
  (coupling implisit), sulit diuji terisolasi — konsisten dengan coverage rendah.
- **Rekomendasi:** pecah `Media3PlaybackService` per tanggung jawab (sesi, transport, notifikasi,
  crossfade), ganti `part` dengan import untuk modul yang benar-benar independen; jangan refactor
  besar sekaligus.
- **Status:** terkonfirmasi.

#### M8. CVE kondisional pada FFmpeg yang dibundel

- **Bukti:** `CVE-2026-8461` (MagicYUV decoder, FFmpeg < 8.1.2, CVSS 8.8); artefak Jellyfin
  1.9.0+1 memakai branch FFmpeg `release/6.0`.
- **Dampak:** hanya terekspos bila decoder MagicYUV diaktifkan di artefak tersebut — belum
  diverifikasi. Namun artefak berada di dalam APK.
- **Rekomendasi:** verifikasi konfigurasi decoder di AAR (atau ganti/upgrade), dan selesaikan C1
  yang sekaligus menghilangkan kelas risiko ini.
- **Status:** potensial, butuh inspeksi artefak.

#### M9. Lirik diambil dari API tidak resmi dengan header dipalsukan + privasi

- **Bukti:**
  - `netease_provider.dart:23-30`, `qq_music_provider.dart:23-36` (`Referer`/`Origin`),
    `kuwo_provider.dart:30-32`, `kugou_provider.dart:35`.
  - Proxy pihak ketiga `lyrics.paxsenix.org` (`apple_music_provider.dart:32`).
  - `lrclib_provider.dart:63` memakai User-Agent placeholder `github.com/user/musicplayer`.
  - `provider_http.dart:15` satu `http.Client` statis tanpa batas ukuran respons; komentar klaim
    "connect timeout 5 detik" padahal hanya ada timeout total 15 detik.
- **Dampak:** judul/artis lagu pengguna dikirim ke 5 layanan pihak ketiga tanpa disclosure Data
  Safety; pelanggaran ToS/risiko IP; respons besar/aneh bisa menekan memori.
- **Rekomendasi:** dokumentasikan & batasi provider default, gunakan UA jujur, batasi ukuran body,
  tambahkan disclosure privasi, evaluasi lisensi lirik.
- **Status:** terkonfirmasi untuk kode; risiko kebijakan bergantung distribusi.

### 2.4 LOW

| ID | Temuan | Bukti | Catatan |
|---|---|---|---|
| L1 | Versi changelog ganda `1.5.38` | `changelog_data.dart:44` dan `:51` | Melanggar aturan "versi tidak boleh dipakai ulang"; `pubspec.yaml:4` = 1.5.41 sudah cocok dengan entri teratas |
| L2 | Dokumentasi usang | `.agents/memory/log-service-persistent.md` menyebut 500 entri & `AudioEngine`; kode 5.000 entri & tanpa persistensi; `lib/services/boot_trace.dart` dirujuk tetapi tidak ada; `README.md` 1 byte | Menyesatkan kontributor berikutnya |
| L3 | File backup ter-commit | `analysis_options.yaml.backup-20260727` | Higiene repo |
| L4 | `allowBackup` default true | `AndroidManifest.xml` tidak menetapkan flag | Prefs berisi path file bisa ikut backup |
| L5 | Cache artwork 500 MB | `ArtworkCacheManager.kt:41` | Besar untuk perangkat 64 GB; LRU sudah ada |
| L6 | Buffer log 5.000 × stack 3.000 char | `log_service/service.dart:6,107,179` | Potensi ~30 MB saat logging aktif; `removeFirst()` O(n) |
| L7 | `_invoke` tanpa timeout | `media3_playback_bridge.dart:244-259` | Bila native tak pernah membalas, `_isLoading` bisa tertahan permanen |
| L8 | `NowPlayingOverlayActivity` menerima `file://` dari app lain | `AndroidManifest.xml:40-41` | Dampak rendah (hanya audio), tetap perlu validasi |
| L9 | `returnDefaultValues=true` & validasi JVM `warning` | `build.gradle:70`, `gradle.properties` | Menyembunyikan mismatch |
| L10 | Workflow duplikat | `ci.yml`, `flutter-check.yml`, `kotlin-tests.yml` | Biaya CI & hasil tidak konsisten |

---

## 3. Best practices yang sudah diterapkan dengan baik

- **Analisis statis ketat**: `strict-casts/inference/raw-types`, 74 lint termasuk
  `discarded_futures`, `unawaited_futures`, `cancel_subscriptions`, `close_sinks`; analyzer bersih
  di lib, test, dan paket native.
- **Audio native**: jalur proses bebas lock/alokasi (`dsp_pipeline.c:182-224`), atomics untuk knob
  lintas thread (`native_audio_runtime.c:33-35`), fail-open saat pipeline belum siap, error
  processor pertama dipertahankan sementara limiter/soft-clipper tetap dijalankan, JNI memeriksa
  `GetDirectBufferCapacity` dan null (`native_dsp_jni.c:70-96`), logging native digerbangi toggle.
- **Ketahanan I/O**: timeout 20 detik untuk query MediaStore
  (`media_store_service.dart:199`), retry backoff `not_ready` 5 percobaan
  (`media3_playback_bridge.dart:244-259`), HTTP retry + 429 cooldown + cancellation, tulis cache
  atomik `tmp` → `rename`.
- **Keamanan dasar**: tidak ada keystore/secret ter-commit (`.gitignore` mencakup `*.jks`,
  `*.keystore`, key.properties), `PendingIntent` memakai `FLAG_IMMUTABLE`, tidak ada konfigurasi
  cleartext, tidak ada WebView, CI memvalidasi keystore/alias/password sebelum build.
- **Rilis Android**: R8 full mode dengan keep rule JNI + decoder FFmpeg, `abiFilters arm64-v8a`,
  minSdk 27 / targetSdk 36, signing CI dipisah dari fallback debug.
- **Arsitektur**: `services/` tidak mengimpor `pages/`; hanya satu bridge yang menyentuh channel
  `musicplayer/media3_*`; queue/shuffle dimiliki native dan Dart hanya mirror; registry modul
  native dengan dispose berurutan.
- **Dokumentasi**: `docs/ARCHITECTURE.md` 800 baris + 124 catatan memori; golden test & matriks
  perangkat.

**Area yang perlu ditingkatkan**: observability, gate CI, pengujian jalur playback, kepatuhan
lisensi, permission UX, dekomposisi kelas besar, dan penyelarasan versi Media3.

---

## 4. Penilaian production readiness

| Aspek | Skor | Alasan |
|---|---:|---|
| Keamanan | **62/100** | Tidak ada secret/cleartext; JNI aman. Namun service diekspor tanpa filter, `READ_MEDIA_IMAGES` berlebihan, dan C1/C2 adalah risiko hukum. |
| Stabilitas | **70/100** | Fail-open, retry, rollback queue bagus; tetapi startup tanpa timeout per langkah dan kegagalan senyap. |
| Performa | **68/100** | DSP native efisien & terukur lewat test; cold start memblokir frame pertama, cache 500 MB, belum ada profiling perangkat. |
| Pengujian | **45/100** | Native/AutoMix kuat; inti playback 0,8–14% dan tidak ada gate CI. |
| Maintainability | **60/100** | Layer bersih & analyzer ketat; kelas 2.700 baris, 157 `part`, docs drift. |
| Kesiapan distribusi/kepatuhan | **25/100** | Konflik GPLv3 vs All Rights Reserved + notis lisensi dibuang. |

**Kesimpulan:** **belum layak produksi/distribusi publik.** Layak untuk penggunaan pribadi di
perangkat target dengan catatan di atas; layak distribusi hanya setelah P0 + P1 selesai.

---

## 5. Risiko yang belum dapat dipastikan tanpa runtime/perangkat

1. Perilaku audio nyata: offload hardware, bit-perfect/AAudio exclusive, crossfade dua deck, AutoMix
   phase-lock, dan benturan JNI saat R8 penuh.
2. Apakah `libffmpegJNI.so` benar-benar dimuat dan decoder mana yang aktif di build rilis.
3. Isi konfigurasi FFmpeg dalam AAR (menentukan eksposur CVE-2026-8461).
4. Perilaku FGS/notifikasi di MIUI 12 (pembatasan background, autostart, battery saver).
5. Durasi cold start nyata dan apakah dialog izin benar-benar menahan frame pertama secara
   signifikan.
6. Performa `BackdropFilter`/shader dengan Impeller dimatikan (`EnableImpeller=false`) di Adreno 618.
7. Apakah deklarasi FGS & Data Safety di Play Console sudah sesuai (tidak dapat diperiksa dari repo).
8. Kebijakan ToS masing-masing penyedia lirik terhadap penggunaan ini.

---

## 6. Roadmap perbaikan (prioritas → dampak → urgensi)

### P0 — Blocker rilis (minggu ini)

1. Selesaikan **C1**: hapus/ganti decoder GPL **atau** relisensikan aplikasi + publikasikan source;
   libatkan review hukum.
2. Pulihkan notis lisensi (**C2**) dan tambahkan layar lisensi open-source.

### P1 — Sebelum menyebarkan APK

3. Observability (**H1**): error selalu terekam, log persisten, crash reporter, unggah simbol
   obfuscation + mapping.
4. Permission UX (**M4**): empty-state izin + tombol Settings + retry; hilangkan
   `READ_MEDIA_IMAGES` (**M2**).
5. Hardening service (**M1**): `onConnect` allowlist + batasi command + validasi `ACTION_PLAY_URI`.
6. CI gate (**M5**): trigger push/PR, satukan workflow, `abortOnError=true`, ambang coverage.

### P2 — Bulan berikutnya

7. Test jalur playback (**H2**): target 60% untuk `audio_service`, `media_store`, `replay_gain`;
   test Kotlin untuk sleep timer/notifikasi/offload.
8. Anggarkan startup (**M3**): `runApp` lebih awal, timeout per langkah, ukur TTFF.
9. Selaraskan Media3/decoder + uji jalur FFmpeg di rilis (**M6**).
10. Pecah `Media3PlaybackService`/`MainActivity` dan kurangi `part` (**M7**).

### P3 — Backlog

11. Kebijakan provider lirik + disclosure privasi (**M9**).
12. Perbaiki drift dokumentasi, duplikasi changelog, file backup, `allowBackup`, batas cache/log
    (**L1–L6, L10**).

---

## 7. Konsolidasi lintas temuan

- **Duplikasi dihapus:** "coverage rendah", "CI dispatch-only", dan "lint tidak menegakkan apa pun"
  semula muncul di workstream Testing dan Code Quality; digabung menjadi H2 + M5 agar akar
  masalahnya satu (tidak ada gate + tidak ada test inti).
- **Konflik diselesaikan:** `AGENTS.md` menyatakan urutan startup "deliberate" — audit performa
  menandainya sebagai risiko. Resolusi: urutannya memang disengaja, tetapi **tidak ada
  timeout/fallback**, sehingga masalahnya bukan urutan melainkan ketiadaan batas waktu; rekomendasi
  tidak menyuruh mengacak ulang urutan.
- **Konflik kritis:** komentar `build.gradle:46` mengakui "GPL v3", sementara `LICENSE` menyatakan
  All Rights Reserved. Ini bukan drift dokumentasi biasa, melainkan kontradiksi kepatuhan yang
  menjadi C1.
- **Prioritas akar masalah:** C1/C2 (lisensi) dan H1 (diagnostik) mendahului perbaikan kode apa pun;
  tanpa keduanya, perbaikan lain tidak dapat divalidasi di lapangan maupun didistribusikan secara
  sah.
- **Konsistensi rekomendasi:** semua area setuju bahwa nilai tertinggi ada pada **menambah test
  jalur playback + gate CI**, karena itu juga yang akan mencegah regresi saat kelas besar dipecah
  pada P2.

---

## Lampiran A — Ringkasan coverage per area

Diukur dari `coverage/lcov.info` setelah 270 test Flutter. File yang tidak pernah dimuat tidak
dihitung, sehingga angka sebenarnya lebih rendah.

| Area | Baris hit / total | Coverage |
|---|---:|---:|
| `services/automix_service` | 1.592 / 2.286 | 69,6% |
| `widgets/pages` | 298 / 940 | 31,7% |
| `widgets/player` | 481 / 1.968 | 24,4% |
| `services/artwork_repository.dart` | 35 / 161 | 21,7% |
| `services/lyrics_service` | 114 / 780 | 14,6% |
| `services/media_store_service.dart` | 16 / 111 | 14,4% |
| `services/replay_gain_service` | 34 / 403 | 8,4% |
| `services/audio` | 21 / 986 | 2,1% |
| `pages/settings_page` | 21 / 1.317 | 1,6% |
| `pages/settings` | 9 / 703 | 1,3% |
| `services/audio_service` | 4 / 504 | 0,8% |
| `pages/playlist_page.dart` | 1 / 217 | 0,5% |
| `pages/log_page` | 1 / 284 | 0,4% |
| `services/song_metadata_service` | 0 / 166 | 0% |
| `services/media_capabilities_service` | 0 / 130 | 0% |

## Lampiran B — Referensi eksternal

- Google Play target API 2026: <https://support.google.com/googleplay/android-developer/answer/11926878>
- Kebijakan foreground service Play: <https://support.google.com/googleplay/android-developer/answer/16559646>
- Izin notifikasi Android 13+ (media exempt): <https://developer.android.com/develop/ui/compose/notifications/notification-permission>
- Photo & Video Permissions policy: <https://support.google.com/googleplay/android-developer/answer/16935362>
- FFmpeg legal: <https://www.ffmpeg.org/legal.html>
- GPLv3: <https://www.gnu.org/licenses/gpl-3.0.en.html>
- FSF FAQ linking: <https://www.gnu.org/licenses/gpl-faq.en.html#GPLStaticVsDynamic>
- Artefak Jellyfin (GPL-3.0): <https://central.sonatype.com/artifact/org.jellyfin.media3/media3-ffmpeg-decoder/1.9.0+1>
- Advisory CVE-2026-8461: <https://github.com/advisories/GHSA-qff7-4q6c-m8h6>

---

*Laporan ini disusun tanpa mengubah kode aplikasi. Semua temuan diberi label status: terkonfirmasi
(dapat dibuktikan dari kode/konfigurasi) atau potensial (memerlukan verifikasi runtime/artefak).*
