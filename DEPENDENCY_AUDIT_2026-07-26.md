# Dependency Audit — musicplayer v1.4.0
**Tanggal audit:** 26 Juli 2026  
**Flutter SDK:** 3.44.8 | **Dart SDK:** 3.12.2  
**Tool:** `flutter pub outdated` + analisis manual changelog pub.dev  

---

## Ringkasan Eksekutif

| Kategori | Jumlah |
|---|---|
| Direct dependency | 14 (+ 2 dev) |
| Semua direct dependency sudah di versi terbaru | ✅ 16/16 |
| Transitive yang bisa di-upgrade langsung | 3 paket |
| Transitive yang tertahan constraint | 11 paket |
| Breaking change ditemukan (sudah on-version) | 4 paket |
| Security issue ditemukan | 0 |
| Dependency konflik antar direct | 0 |
| Constraint blocker utama | `native_audio_runtime` pins toolchain native-assets |

> **Kondisi keseluruhan: SEHAT.** Semua direct dependency sudah di versi terbaru. Tidak ada security issue. Satu-satunya area perhatian adalah native-assets toolchain (hooks/code_assets/native_toolchain_c) yang tertahan oleh constraint di `native_audio_runtime/pubspec.yaml`, dan satu bug fix penting di `flutter_cache_manager` 3.4.2 yang tersedia via `flutter pub upgrade`.

---

## Bagian 1 — Output `flutter pub outdated`

### Direct Dependencies — Semua Up-to-Date

| Package | Current | Upgradable | Resolvable | Latest | Status |
|---|---|---|---|---|---|
| audio_session | 0.2.4 | 0.2.4 | 0.2.4 | 0.2.4 | ✅ |
| cached_network_image | 3.4.1 | 3.4.1 | 3.4.1 | 3.4.1 | ✅ |
| cupertino_icons | 1.0.9 | 1.0.9 | 1.0.9 | 1.0.9 | ✅ |
| font_awesome_flutter | 11.0.0 | 11.0.0 | 11.0.0 | 11.0.0 | ✅ |
| http | 1.6.0 | 1.6.0 | 1.6.0 | 1.6.0 | ✅ |
| path | 1.9.1 | 1.9.1 | 1.9.1 | 1.9.1 | ✅ |
| path_provider | 2.1.6 | 2.1.6 | 2.1.6 | 2.1.6 | ✅ |
| permission_handler | 12.0.3 | 12.0.3 | 12.0.3 | 12.0.3 | ✅ |
| rxdart | 0.28.0 | 0.28.0 | 0.28.0 | 0.28.0 | ✅ |
| scrollable_positioned_list | 0.3.8 | 0.3.8 | 0.3.8 | 0.3.8 | ✅ |
| shared_preferences | 2.5.5 | 2.5.5 | 2.5.5 | 2.5.5 | ✅ |
| text_scroll | 0.2.1 | 0.2.1 | 0.2.1 | 0.2.1 | ✅ |
| url_launcher | 6.3.2 | 6.3.2 | 6.3.2 | 6.3.2 | ✅ |
| native_audio_runtime | 0.1.0 (path) | — | — | local | ✅ |
| flutter_launcher_icons (dev) | 0.14.4 | 0.14.4 | 0.14.4 | 0.14.4 | ✅ |
| flutter_lints (dev) | 6.0.0 | 6.0.0 | 6.0.0 | 6.0.0 | ✅ |

### Transitive Dependencies — Yang Tertinggal

> `[*]` = versi tidak sama dengan latest yang tersedia

| Package | Locked | Upgradable | Resolvable | Latest | Bisa upgrade? |
|---|---|---|---|---|---|
| flutter_cache_manager | 3.4.1 | **3.4.2** | 3.4.2 | 3.4.2 | ✅ Ya |
| synchronized | 3.4.1 | **3.4.1+1** | 3.4.1+1 | 3.4.1+1 | ✅ Ya |
| posix (dev) | 6.5.0 | **6.5.2** | 6.5.2 | 6.5.2 | ✅ Ya |
| native_toolchain_c | 0.17.6 | ✗ | 0.17.6 | 0.19.3 | ❌ Constrained |
| hooks | 1.0.3 | ✗ | 1.0.3 | 2.1.0 | ❌ Constrained |
| code_assets | 1.0.0 | ✗ | 1.0.0 | 1.2.1 | ❌ Constrained |
| record_use | 0.6.0 | ✗ | 0.6.0 | 1.0.0 | ❌ Constrained |
| meta | 1.18.0 | ✗ | 1.18.0 | 1.19.0 | ❌ Flutter SDK |
| vector_math | 2.2.0 | ✗ | 2.2.0 | 2.4.1 | ❌ Flutter SDK |
| package_config | 2.2.0 | ✗ | 2.2.0 | 3.0.0 | ❌ Constrained |
| objective_c | 9.3.0 | ✗ | 9.3.0 | 9.4.1 | ❌ Constrained |
| cli_util (dev) | 0.4.2 | ✗ | 0.4.2 | 0.5.2 | ❌ Constrained |
| matcher (dev) | 0.12.19 | ✗ | 0.12.19 | 0.12.20 | ❌ Constrained |
| test_api (dev) | 0.7.11 | ✗ | 0.7.11 | 0.7.13 | ❌ Constrained |

---

## Bagian 2 — Audit Per Direct Dependency

### 1. `audio_session` `^0.2.3` → locked `0.2.4`

| | |
|---|---|
| **Versi locked** | 0.2.4 |
| **Versi terbaru** | 0.2.4 |
| **Breaking change** | Tidak (di 0.2.4); Ya di 0.2.0 |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `0.2.4` (Jun 2026): Support AGP 9, migrasi build files ke `.kts`. Tidak ada breaking change.
- `0.2.3`: Bug fix penting — **`audioAttributes` yang di-set diabaikan di Android** (sudah ter-fix, tapi ini bug serius yang perlu diketahui jika pakai custom audio attributes). Fix NPE di device encoding.
- `0.2.0`: **Breaking** — `AUDIO_SESSION_MICROPHONE=0` by default di iOS, migrasi ke Kotlin, min Flutter 3.27, AGP ≥ 8.

**Perubahan Android:** AGP 9 support, migrasi .kts build files. Tidak ada perubahan behavior audio.  
**Perubahan iOS:** Tidak ada di 0.2.3/0.2.4.  
**Perubahan Flutter SDK min:** Ya di 0.2.0 → Flutter 3.27 (sudah terpenuhi di project: 3.44).  
**Perubahan Dart SDK min:** Tidak eksplisit di 0.2.3/0.2.4.  
**Migrasi wajib:** Tidak ada.

**Catatan untuk project:** Bug fix `audioAttributes` di 0.2.3 relevan — project ini pakai `audio_session` untuk set audio focus/routing di Android. Versi yang di-lock (0.2.4) sudah mengandung fix ini.

---

### 2. `cached_network_image` `^3.4.1` → locked `3.4.1`

| | |
|---|---|
| **Versi locked** | 3.4.1 |
| **Versi terbaru** | 3.4.1 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `3.4.1` (Agt 2024): Target `js_interop` untuk Wasm support.
- `3.4.0`: Perubahan error reporting — error dikirim sebagai stream, bukan di-rethrow. Debug messages ditingkatkan.

**Perubahan Android/iOS:** Tidak ada perubahan platform-specific di 3.4.x.  
**Catatan:** Package ini sudah 23 bulan tidak di-update (Aug 2024). Ini menandakan stable tapi juga _potensial abandoned_. Perlu dipantau apakah maintainer masih aktif.  
**Dampak playback:** Tidak ada — dipakai untuk artwork di UI, bukan audio path.  
**Dampak cache:** Dipakai bersamaan dengan `flutter_cache_manager` (dep transitifnya). Bug fix di `flutter_cache_manager` 3.4.2 (`removeFile` path salah) berdampak tidak langsung ke `cached_network_image`.

---

### 3. `http` `^1.6.0` → locked `1.6.0`

| | |
|---|---|
| **Versi locked** | 1.6.0 |
| **Versi terbaru** | 1.6.0 |
| **Breaking change** | Ya (di 1.6.0 sendiri) |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low–Medium |
| **Rekomendasi** | Pertahankan, tapi periksa lyrics provider request body |

**Changelog ringkas:**
- `1.6.0`: **Breaking** — `Request.body` hanya menambah charset parameter untuk `text/*` dan `xml/*` MIME types. Untuk binary/JSON tanpa MIME type yang jelas, charset tidak ditambah lagi. Sesuai RFC-8259.
- `1.5.0`: Support abort request, fix IOClient stream cancel.
- `1.4.0`: Fix default encoding `application/json` dari latin1 → utf8 (penting!).
- `1.3.0`: `BrowserClient` beralih dari `XMLHttpRequest` ke Fetch API.

**Perubahan Android:** Tidak ada platform-specific change.  
**Perubahan iOS:** Tidak ada.  
**Migrasi wajib:** Periksa kode lyrics provider yang mengirim request body dengan MIME type non-text — jika ada request `POST` dengan binary payload yang bergantung pada charset auto-injection, behavior berubah.

**Dampak untuk project:** Semua lyrics API call adalah `GET` dengan JSON response — tidak ada `POST` body yang bermasalah. **Tidak ada dampak runtime.**

---

### 4. `path_provider` `^2.1.5` → locked `2.1.6`

| | |
|---|---|
| **Versi locked** | 2.1.6 |
| **Versi terbaru** | 2.1.6 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `2.1.6`: Updates min SDK ke Flutter 3.38/Dart 3.10. Perubahan dokumentasi.
- Tidak ada perubahan behavior.

**Perubahan Android (transitive `path_provider_android` 2.3.1):**
- `2.3.1`: **Menghapus dependency pada `PathUtils`** untuk menghindari `ClassNotFoundException` saat release mode. Ini adalah **bug fix kritikal** yang pernah menyebabkan crash di release APK.
- `2.3.0`: Implementasi internal beralih ke JNI (dari Kotlin biasa). Ini adalah perubahan arsitektur besar di backend, tapi API publik tidak berubah.

**Dampak untuk project:** path_provider dipakai untuk artwork cache, lyrics cache, SQLite (MetadataCacheDb). Bug fix ClassNotFoundException di 2.3.1 sudah ter-include di locked version ini — aman.

---

### 5. `permission_handler` `^12.0.3` → locked `12.0.3`

| | |
|---|---|
| **Versi locked** | 12.0.3 |
| **Versi terbaru** | 12.0.3 |
| **Breaking change** | Ya (di 12.0.0) |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `12.0.3`: Perbaikan dokumentasi README saja.
- `12.0.2`: Dokumentasi Swift Package Manager.
- `12.0.0`: **Breaking** — `permission_handler_android` di-update ke 13.0.0, `compileSdkVersion` Android diupdate ke **35**.
- `11.1.0`: Penambahan permission `Permission.calendarFullAccess` (iOS 17+), deprecasi `Permission.calendar`.

**Perubahan Android:** `compileSdkVersion 35` adalah perubahan signifikan. Perlu dipastikan `android/app/build.gradle` di project ini sudah pakai `compileSdkVersion 35` agar konsisten.

**Perubahan iOS:** `IPHONEOS_DEPLOYMENT_TARGET` diupdate ke 12.0 (dari 11.0).

**Dampak untuk project:** `READ_EXTERNAL_STORAGE` di Android 13+ sudah digantikan oleh `READ_MEDIA_AUDIO`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`. permission_handler 12.x sudah menghandle ini. Pastikan `AndroidManifest.xml` sudah pakai permission yang benar untuk Android 13+.

---

### 6. `shared_preferences` `^2.5.3` → locked `2.5.5`

| | |
|---|---|
| **Versi locked** | 2.5.5 |
| **Versi terbaru** | 2.5.5 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `2.5.5`: Fix dartdoc comments, tidak ada perubahan behavior.
- `2.5.4`: Update DevTools extension dependencies, min SDK bump ke Flutter 3.35/Dart 3.9.
- `2.5.3`: Fix bug di example app saja.

**Perubahan Android/iOS:** Tidak ada perubahan runtime.  
**Dampak untuk project:** Dipakai untuk queue persistence, settings, sleep timer, library order. Aman sepenuhnya.

---

### 7. `rxdart` `^0.28.0` → locked `0.28.0`

| | |
|---|---|
| **Versi locked** | 0.28.0 |
| **Versi terbaru** | 0.28.0 |
| **Breaking change** | Ya (di 0.28.0 sendiri) |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low (sudah on-version) |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas (0.28.0 — Jun 2024):**
- **Breaking** — `Notification` → `StreamNotification`, `Kind` → `NotificationKind`
- **Breaking** — `ForkJoinStream.combine2..9` → `ForkJoinStream.join2..9`
- **Breaking** — `Rx.using`/`UsingStream`: positional params → named params
- `switchMap` sekarang pause outer stream saat inner di-cancel
- Mendukung Dart SDK > 3.0

**Dampak untuk project:** Project sudah pakai 0.28.0, jadi breaking changes ini sudah ditangani. rxdart dipakai untuk stream playback (BehaviorSubject, queue stream). Tidak ada masalah.

---

### 8. `scrollable_positioned_list` `^0.3.8` → locked `0.3.8`

| | |
|---|---|
| **Versi locked** | 0.3.8 |
| **Versi terbaru** | 0.3.8 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `0.3.8`: Tambah `ScrollOffsetController`, bump min SDK ke 2.15.
- `0.3.7`: Tambah `ScrollOffsetListener`.

**Catatan:** Package sudah lama tidak di-update (versi terakhir 0.3.8, min SDK masih 2.15). Dipakai untuk lyrics sync scroll. Stabil tapi potentially abandoned — perlu dipantau.

---

### 9. `text_scroll` `^0.2.1` → locked `0.2.1`

| | |
|---|---|
| **Versi locked** | 0.2.1 |
| **Versi terbaru** | 0.2.1 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

Dipakai untuk scrolling teks judul lagu. Package kecil, stabil, tidak ada issue.

---

### 10. `font_awesome_flutter` `^11.0.0` → locked `11.0.0`

| | |
|---|---|
| **Versi locked** | 11.0.0 |
| **Versi terbaru** | 11.0.0 |
| **Breaking change** | Ya (di 11.0.0 sendiri — sudah ditangani) |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low (sudah on-version) |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas (11.0.0):**
- **Breaking** — `FaIconData` tidak lagi implements `IconData`. `FaIcon` sekarang hanya menerima `FaIconData`.
- **Breaking** — Test finder `find.byIcon` harus pakai `.data`: `find.byIcon(FontAwesomeIcons.foo.data)`.
- Upgrade ke Font Awesome 7.2.0.

**Dampak untuk project:** Breaking changes sudah ditangani saat upgrade ke 11.0.0. Tidak ada dampak runtime.

---

### 11. `url_launcher` `^6.3.2` → locked `6.3.2`

| | |
|---|---|
| **Versi locked** | 6.3.2 |
| **Versi terbaru** | 6.3.2 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

**Changelog ringkas:**
- `6.3.2`: Update README, min SDK ke Flutter 3.27/Dart 3.6. Tidak ada perubahan runtime.
- `6.3.0`: Tambah `BrowserConfiguration` parameter untuk Android Custom Tabs / SFSafariViewController.

**Dampak Android:** `url_launcher_android` 6.3.32 sudah di lock, tidak ada isu.

---

### 12. `cupertino_icons` `^1.0.8` → locked `1.0.9`

| | |
|---|---|
| **Versi locked** | 1.0.9 |
| **Versi terbaru** | 1.0.9 |
| **Breaking change** | Tidak |
| **Status** | ✅ Up-to-date |
| **Risk level** | Low |
| **Rekomendasi** | Pertahankan |

Font icon saja, tidak ada platform-specific behavior. Stable.

---

### 13. `path` `^1.9.0` → locked `1.9.1`

| | |
|---|---|
| **Versi locked** | 1.9.1 |
| **Versi terbaru** | 1.9.1 |
| **Status** | ✅ Up-to-date, **Risk level:** Low |

Pure Dart path manipulation utility. Tidak ada platform dependency. Aman sepenuhnya.

---

### 14. `native_audio_runtime` (local path) → `0.1.0`

| | |
|---|---|
| **Versi locked** | 0.1.0 (path: `./native_audio_runtime`) |
| **Status** | Local package, tidak relevan untuk pub.dev versioning |
| **Risk level** | Medium (sebagai constraint blocker) |

**Masalah:** Package ini adalah **constraint blocker** untuk seluruh native-assets toolchain. Dependency-nya yang ketat di `pubspec.yaml`:

```yaml
native_toolchain_c: ^0.17.4   # Latest: 0.19.3
hooks: ^1.0.0                  # Latest: 2.1.0 (major version!)
code_assets: ^1.0.0            # Latest: 1.2.1
record_use: ^0.6.0             # Latest: 1.0.0 (major version!)
```

Ini mencegah 4 transitive package di-upgrade ke versi terbaru. Dampak: hanya di build toolchain, tidak ada efek runtime pada app Android yang sudah terkompilasi.

---

### 15. `flutter_lints` (dev) `^6.0.0` → locked `6.0.0`

Up-to-date. Tidak ada perubahan yang relevan untuk runtime.

---

### 16. `flutter_launcher_icons` (dev) `^0.14.4` → locked `0.14.4`

Up-to-date. Dipakai hanya saat generate launcher icon, tidak ada runtime dependency.

---

## Bagian 3 — Audit Mendalam: Kategori Khusus

### 🎵 Audio & Media

#### `audio_session` 0.2.4
**Status: ✅ Aman, sudah terbaru**

| Aspek | Kondisi |
|---|---|
| Playback | Tidak berubah di 0.2.3/0.2.4 |
| MediaSession | Tidak ada perubahan |
| Android native | AGP 9 support, .kts migration (build-time saja) |
| JNI | Tidak ada perubahan JNI |
| Bug fix relevan | `audioAttributes` ignored on Android sudah di-fix di 0.2.3 → **penting untuk audio routing** |
| Battery | Tidak ada dampak |
| Performance | Tidak ada dampak |

**Yang perlu diketahui:** Bug `audioAttributes` di-ignore di Android (fix di 0.2.3) relevan untuk project ini. Versi locked 0.2.4 sudah termasuk fix ini. Pastikan kode Dart yang set `audioAttributes` (usage `audio_session`) memang dijalankan sebelum play — sekarang efeknya sudah benar di Android.

---

### 🔐 Permission

#### `permission_handler` 12.0.3 + `permission_handler_android` 13.0.1
**Status: ✅ Aman, sudah terbaru**

| Aspek | Kondisi |
|---|---|
| compileSdkVersion | Harus 35 (breaking change di 12.0.0) |
| MediaStore | Permission `READ_MEDIA_AUDIO` tersedia via `Permission.audio` |
| Android native | permission_handler_android 13.0.1: kompilasi ulang dengan targetSdk 35 |
| Dampak playback | Tidak langsung |
| Dampak storage/MediaStore | Jika app belum minta `READ_MEDIA_AUDIO` (Android 13+), akses library kosong |

**Yang perlu diverifikasi:** Pastikan `android/app/build.gradle` sudah set:
```groovy
compileSdkVersion 35
targetSdkVersion 35
```
Jika masih 33 atau 34, build akan tetap berhasil tapi ada potensi behavior mismatch dengan permission_handler_android 13.

---

### 🗄️ Cache & Storage

#### `cached_network_image` 3.4.1
**Status: ✅ Aman, sudah terbaru**

| Aspek | Kondisi |
|---|---|
| Cache disk | Ditangani oleh `flutter_cache_manager` (transitive) |
| Memory cache | Stabil |
| Bug kritis | Tidak ada di 3.4.1 |
| Dampak artwork | Aman, tidak ada regresi diketahui |

#### `flutter_cache_manager` 3.4.1 (locked) → **3.4.2 tersedia**
**Status: ⚠️ Ada bug fix penting — upgrade direkomendasikan**

| Aspek | Kondisi |
|---|---|
| Bug fix utama | `removeFile()` menghapus dari path yang **salah** di 3.4.1 |
| Dart SDK min baru | 3.8.0 (project pakai 3.12.2 ✅) |
| Breaking change | Tidak |
| Dampak artwork cache | `removeFile()` digunakan saat evict cache artwork — jika terpanggil, file di 3.4.1 tidak terhapus dari path yang benar |
| Dampak battery/storage | Di 3.4.1, cache disk tidak ter-clean dengan benar saat `removeFile()` dipanggil → storage leak potensial |

**Rekomendasi: UPGRADE via `flutter pub upgrade flutter_cache_manager`.**  
Tidak ada breaking change. Bug fix langsung relevan karena artwork cache app ini menggunakan flutter_cache_manager sebagai backend disk.

---

### 🌐 Network

#### `http` 1.6.0
**Status: ✅ Aman, sudah terbaru**

| Aspek | Kondisi |
|---|---|
| Lyrics API calls | Semua GET request, tidak terpengaruh breaking change charset |
| Android native | Tidak ada perubahan |
| Performance | Tidak ada dampak |
| Battery | Tidak ada dampak |
| Security | Tidak ada CVE diketahui |

**Breaking change charset di 1.6.0:** Hanya relevan jika ada POST request dengan MIME type non-text yang butuh auto-charset. Project ini hanya melakukan GET ke lyrics providers (LRCLIB, NetEase, Kugou, Kuwo, QQMusic). **Tidak ada dampak.**

---

### 💾 Storage (path_provider + shared_preferences)

#### `path_provider` 2.1.6 + `path_provider_android` 2.3.1
**Status: ✅ Aman, sudah terbaru**

| Aspek | Kondisi |
|---|---|
| Bug fix kritikal | ClassNotFoundException di release mode (fix di 2.3.1) ✅ sudah ter-include |
| JNI backend baru | path_provider_android 2.3.0 beralih ke JNI — tapi API publik tidak berubah |
| Dampak artwork cache | Aman |
| Dampak SQLite (MetadataCacheDb) | Aman |
| Dampak lyrics cache | Aman |

#### `shared_preferences` 2.5.5
**Status: ✅ Aman, sudah terbaru.** Hanya docs fix, tidak ada perubahan behavior.

---

## Bagian 4 — Analisis Transitive Dependencies (pubspec.lock)

### 4.1 Package yang Patut Diperhatikan

#### `jni` 1.0.0 + `jni_flutter` 1.0.1 (transitive dari path_provider_android)

Package `jni` 1.0.0 adalah **major breaking release** dari 0.x:
- Semua Java wrapper class dimigrasi ke Dart extension types
- `JniException` dihapus → exceptions sekarang sebagai `JThrowable`
- API collection (`JList`, `JMap`, dsb.) berubah drastis
- `Jni.androidApplicationContext` dipindah ke `jni_flutter` package baru

**Dampak untuk project:** `jni` dan `jni_flutter` hanya dipakai secara _internal_ oleh `path_provider_android`. Project ini tidak memanggil JNI API secara langsung dari Dart (project pakai MethodChannel / JNI native sendiri, bukan Dart `package:jni`). **Tidak ada dampak langsung.**

#### `sqflite` 2.4.3 (transitive dari flutter_cache_manager)

Dipakai sebagai backend database untuk disk cache `flutter_cache_manager`. Versi 2.4.3 adalah terbaru. Stabil, tidak ada isu.

#### `synchronized` 3.4.1 → **3.4.1+1 tersedia**

Dipakai oleh `sqflite_common`. Update 3.4.1+1 hanya memperbaiki dokumentasi dan bumps Dart SDK requirement ke 3.12 (sudah terpenuhi). Aman di-upgrade.

#### `vector_math` 2.2.0 → latest 2.4.1 (tidak bisa upgrade)

Dikunci oleh Flutter SDK 3.44.8 yang bundle-kan `vector_math` 2.2.0. Untuk upgrade, harus tunggu Flutter SDK update. Tidak ada dampak fungsional — versi 2.2.0 stabil untuk penggunaan di Flutter.

#### `meta` 1.18.0 → latest 1.19.0 (tidak bisa upgrade)

Sama seperti vector_math — dikunci oleh Flutter SDK. record_use 1.0.0 (latest) mendepend pada `meta ^1.19.0` yang menyebabkan konflik, sehingga record_use juga tidak bisa naik. Tidak ada dampak fungsional.

### 4.2 Constraint Blocker Map (native_audio_runtime)

```
native_audio_runtime/pubspec.yaml
├── native_toolchain_c: ^0.17.4  →  blocks upgrade ke 0.18.x / 0.19.x
├── hooks: ^1.0.0               →  blocks upgrade ke 2.x (major version!)
├── code_assets: ^1.0.0         →  blocks upgrade ke 1.1.x / 1.2.x
└── record_use: ^0.6.0          →  blocks upgrade ke 1.0.0 (major version!)
```

**Dampak runtime:** TIDAK ADA. Semua ini adalah Dart _build tools_ yang dipakai saat kompilasi FFI package, bukan saat runtime di Android.  
**Dampak build:** Native_audio_runtime menggunakan `hooks` package untuk build hooks (mengkompilasi C code). Versi 1.0.3 yang locked masih berfungsi — build tidak rusak.  
**Kapan perlu diupgrade:** Saat mau upgrade Flutter SDK signifikan (misal ke Flutter 4.x), atau saat `native_toolchain_c` 0.19+ punya fitur yang dibutuhkan (saat ini tidak ada kebutuhan).

---

### 4.3 Dependency Override

**Tidak ada** `dependency_overrides` di `pubspec.yaml`. Clean.

---

### 4.4 Package Tidak Terpakai

Semua package di `pubspec.lock` dapat dilacak ke penggunaan melalui dependency tree. Tidak ada _orphan package_ yang tersisa tanpa jalur dep.

---

## Bagian 5 — Tabel Rekomendasi Lengkap

### Direct Dependencies

| Package | Locked | Rekomendasi | Alasan |
|---|---|---|---|
| audio_session | 0.2.4 | ✅ Pertahankan | Sudah terbaru, bug fix audioAttributes sudah ter-include |
| cached_network_image | 3.4.1 | ✅ Pertahankan | Sudah terbaru, stabil |
| cupertino_icons | 1.0.9 | ✅ Pertahankan | Sudah terbaru |
| font_awesome_flutter | 11.0.0 | ✅ Pertahankan | Sudah terbaru, breaking changes sudah ditangani |
| http | 1.6.0 | ✅ Pertahankan | Sudah terbaru, tidak ada dampak untuk project ini |
| path | 1.9.1 | ✅ Pertahankan | Sudah terbaru |
| path_provider | 2.1.6 | ✅ Pertahankan | Sudah terbaru, ClassNotFoundException fix sudah ter-include |
| permission_handler | 12.0.3 | ✅ Pertahankan | Sudah terbaru, verifikasi compileSdkVersion 35 |
| rxdart | 0.28.0 | ✅ Pertahankan | Sudah terbaru |
| scrollable_positioned_list | 0.3.8 | ✅ Pertahankan | Sudah terbaru, stabil |
| shared_preferences | 2.5.5 | ✅ Pertahankan | Sudah terbaru |
| text_scroll | 0.2.1 | ✅ Pertahankan | Sudah terbaru |
| url_launcher | 6.3.2 | ✅ Pertahankan | Sudah terbaru |
| flutter_lints (dev) | 6.0.0 | ✅ Pertahankan | Sudah terbaru |
| flutter_launcher_icons (dev) | 0.14.4 | ✅ Pertahankan | Sudah terbaru |

### Transitive Dependencies

| Package | Locked | Tersedia | Rekomendasi | Alasan |
|---|---|---|---|---|
| flutter_cache_manager | 3.4.1 | 3.4.2 | ⬆️ **Upgrade segera** | Bug fix `removeFile()` — potensial storage leak di artwork cache |
| synchronized | 3.4.1 | 3.4.1+1 | ⬆️ Upgrade nanti | Hanya docs + Dart 3.12 compat — sudah compatible, low priority |
| posix (dev) | 6.5.0 | 6.5.2 | ⬆️ Upgrade nanti | Dev toolchain, tidak ada dampak runtime |
| native_toolchain_c | 0.17.6 | 0.19.3 | 🔒 Jangan sekarang | Butuh bump constraint di native_audio_runtime — tangguhkan sampai ada kebutuhan fitur 0.19.x |
| hooks | 1.0.3 | 2.1.0 | 🔒 Jangan sekarang | Major version bump, butuh migrasi native_audio_runtime |
| code_assets | 1.0.0 | 1.2.1 | 🔒 Jangan sekarang | Constrained oleh native_audio_runtime |
| record_use | 0.6.0 | 1.0.0 | 🔒 Jangan sekarang | Major version, constrained |
| meta | 1.18.0 | 1.19.0 | 🔒 Tidak bisa | Dikunci oleh Flutter SDK — upgrade saat Flutter SDK naik |
| vector_math | 2.2.0 | 2.4.1 | 🔒 Tidak bisa | Dikunci oleh Flutter SDK |
| package_config | 2.2.0 | 3.0.0 | 🔒 Tidak bisa | Constrained oleh toolchain |
| jni | 1.0.0 | 1.0.0 | ✅ Sudah terbaru | Tidak langsung dipakai project |
| objective_c | 9.3.0 | 9.4.1 | 🔒 Tidak relevan | iOS-only, project target Android |
| matcher (dev) | 0.12.19 | 0.12.20 | 🔒 Biarkan | Dev dep, tidak ada dampak build/runtime |
| cli_util (dev) | 0.4.2 | 0.5.2 | 🔒 Biarkan | Dev dep |
| test_api (dev) | 0.7.11 | 0.7.13 | 🔒 Biarkan | Dev dep |

---

## Bagian 6 — Action Items

### Prioritas Tinggi
1. **Upgrade `flutter_cache_manager` 3.4.1 → 3.4.2**  
   Jalankan: `flutter pub upgrade flutter_cache_manager`  
   Alasan: Bug `removeFile()` path salah → potensial artwork cache tidak ter-clean dengan benar.  
   Risk: **Low** (tidak ada breaking change).

2. **Verifikasi `compileSdkVersion 35` di android/app/build.gradle**  
   `permission_handler_android` 13.x mengharuskan compileSdkVersion 35. Jika belum diset, ada potensi warning/issue saat build.

### Prioritas Rendah
3. Upgrade `synchronized` 3.4.1 → 3.4.1+1 (docs only, bisa bersamaan dengan upgrade lain)
4. Upgrade `posix` 6.5.0 → 6.5.2 (dev dep, tidak ada dampak runtime)

### Ditangguhkan (tidak urgent)
5. Upgrade native-assets toolchain (`hooks`, `native_toolchain_c`, `code_assets`, `record_use`) di `native_audio_runtime` — perlu investigasi compatibility dulu, lakukan hanya jika ada kebutuhan fitur baru di 0.19.x / 2.x.

### Monitor
6. `cached_network_image` belum di-update sejak Agustus 2024 — pantau apakah package masih aktif atau perlu alternatif.
7. `scrollable_positioned_list` juga tidak update sejak lama — sama, pantau.

---

## Bagian 7 — Security Scan

| Area | Temuan |
|---|---|
| CVE di direct deps | **Tidak ada** |
| CVE di transitive deps | **Tidak ada** |
| Package deprecated | **Tidak ada** yang deprecated |
| Package dengan akses network (http) | Sudah di versi terbaru |
| Package dengan akses storage | Sudah di versi terbaru |
| Package dengan permission sensitive | Sudah di versi terbaru |
| Dependency override yang mencurigakan | **Tidak ada** |

---

*Audit dihasilkan 26 Juli 2026. Data versi berdasarkan pub.dev pada tanggal audit. Re-run `flutter pub outdated` untuk cek update terbaru.*
