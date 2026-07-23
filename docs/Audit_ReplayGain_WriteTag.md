# Audit Menyeluruh — ReplayGain Write Tag

**Tanggal:** 2026-07-20  
**Scope:** Fitur penulisan tag ReplayGain saja (bukan playback/DSP/loudness analysis)  
**File yang diaudit:** `tag_writer.cpp/h`, `metadata_region.cpp/h`, `replaygain_jni.cpp`, `jni_common.h`, `ReplayGainNative.kt`, `ReplayGainService.kt`, `ReplayGainBridge.kt`, `MediaStoreWriteGate.kt`, `ReplayGainModels.kt`, `MainActivity.kt` (bagian ReplayGain), `service.dart` (ReplayGainService Dart), `batch_scan_section.dart`, `CMakeLists.txt`

---

## 1. Arsitektur & Flow

```
UI (Settings → Scan Library)
│  batch_scan_section.dart → _BatchScanSectionState._startScan()
│  → ReplayGainService.scanLibrary(songs, writeTags: true)
│
├─ [pra-otorisasi batch] ─────────────────────────────────────────────
│  MethodChannel('musicplayer/media_store') → 'requestReplayGainWriteAccessBatch'
│  MainActivity.kt → requestReplayGainWriteAccessBatch(songIds)
│  → MediaStoreWriteGate.ensureWriteAccessBatch()
│    (Android 11+: 1 dialog untuk semua; Android 10: per-file)
│
└─ [per-lagu, 2 paralel] ─────────────────────────────────────────────
   ReplayGainService.scanOneSong(song, writeTags=true)
   │
   ├─ MethodChannel → 'scanTrack' → replayGainBridge.scanTrack(path) [replayGainScanExecutor]
   │  → ReplayGainService.kt::scanTrack(path)
   │  → PcmDecoder.decode() → EburTrackSession (JNI → libebur128)
   │
   └─ MethodChannel → 'writeReplayGain' [main thread]
      → MainActivity.kt::requestReplayGainWriteAccess(songId)
        → MediaStoreWriteGate.ensureWriteAccess() [grant sudah ada → langsung lolos]
      → submitBackground(metadataExecutor) [background, serialized]
      → replayGainBridge.writeReplayGain(args)
      → ReplayGainBridge.kt::runFdMutation()
        │
        ├─ openFd(songId)  →  contentResolver.openFileDescriptor(uri, "rw")
        │  → writePfd.detachFd()  → native mengambil ownership fd
        │
        ├─ ReplayGainService.writeReplayGainFd(fd, ...)
        │  → ReplayGainNative.nativeWriteReplayGainTagsFd(fd, ...) [JNI]
        │  → replaygain_jni.cpp::Java_..._nativeWriteReplayGainTagsFd()
        │  → tag_writer.cpp::WriteReplayGainTagsFd(fd, req, &prior, &region)
        │    ├─ metadata_region.cpp::DetermineMetadataRegionSize(fd, format)
        │    │  [ID3v2: baca 10-byte header; FLAC: walk block chain; Ogg: walk pages]
        │    ├─ ReadRegion(fd, size, &out_region.bytes)  [pread, backup]
        │    ├─ FsyncGuard fsync_guard(fd)  [dup(fd) untuk fsync setelah save]
        │    ├─ TagLib::FileStream stream(fd, readOnly=false)
        │    ├─ TagLib::{MPEG/FLAC/OggVorbis/OggOpus}::File file(&stream)
        │    ├─ Set tag fields  [SetTxxx / SetXiphField / ApplyReplayGainFields]
        │    ├─ file.save()  [TagLib tulis ulang region metadata, audio tidak disentuh]
        │    └─ fsync_guard.Sync()  [fsync(dup_fd)]
        │
        ├─ [TagLib menutup fd via fclose() dalam destructor FileStream]
        │
        ├─ openFd(songId) → verifyFd.detachFd()
        ├─ ReplayGainService.verifyWriteFd(fd, ...)
        │  → nativeVerifyReplayGainTagsFd() → VerifyReplayGainTagsFd()
        │    [re-baca tag, bandingkan nilai + sentinel title/artist/album]
        │
        └─ [jika verify gagal]
           openFd(songId) → restoreFd.detachFd()
           ReplayGainService.restoreRegionFd(fd, format, region)
           → nativeRestoreMetadataRegionFd() → RestoreMetadataRegionFd()
             [DetermineMetadataRegionSize → stream.insert(backup, 0, currentSize)]
```

**Kesimpulan konektivitas:** Semua tahapan terhubung dan bisa dieksekusi. Tidak ada tahap yang tergantung callback yang tidak pernah terhubung.

---

## 2. Temuan

---

### [HIGH-1] Fd leak ketika `TagLib::FileStream::isOpen()` bernilai false

**Severity:** High  
**Lokasi:** `tag_writer.cpp` — fungsi `WriteReplayGainTagsFd` (baris ~466–468), `RemoveReplayGainTagsFd` (~534–537), `RestoreMetadataRegionFd` (~717–719)

**Penjelasan:**

Ketiga fungsi memanggil `TagLib::FileStream stream(fd, openReadOnly=false/true)` lalu langsung memeriksa `stream.isOpen()`. Di dalam TagLib, konstruktor FileStream memanggil `::fdopen(fd, mode)`. Jika `fdopen` gagal (misalnya: tekanan memori tinggi, fd non-seekable), TagLib menyimpan `d->file = nullptr` dan destruktornya tidak memanggil `fclose()`. Artinya, fd ASLI yang diberikan ke FileStream tidak pernah ditutup siapapun.

```cpp
// Kondisi bermasalah — di ketiga fungsi:
FsyncGuard fsync_guard(fd);          // dup(fd) → fd baru untuk fsync, bukan fd asli
TagLib::FileStream stream(fd, ...);  // jika fdopen gagal: fd ASLI tidak ditutup
if (!stream.isOpen()) return WriteResult::kPermissionFailure;  // fd bocor
```

`FsyncGuard` hanya menutup hasil `dup(fd)`, bukan fd asli yang sekarang dimiliki (atau seharusnya dimiliki) oleh FileStream.

**Dampak:** Setiap kali `fdopen` gagal, satu fd bocor. Android ART memiliki limit ~1024 fd per proses. Pada batch scan besar di kondisi memori ketat, akumulasi fd leak bisa menyebabkan proses kehabisan fd → crash.

**Risiko praktis:** Rendah dalam kondisi normal (fdopen jarang gagal untuk fd "rw" dari MediaStore), tetapi bisa terjadi di perangkat dengan RAM <1 GB atau sistem yang sedang kehabisan memori.

**Solusi:** Tutup fd secara eksplisit sebelum return ketika `!stream.isOpen()`:

```cpp
// Di WriteReplayGainTagsFd, RemoveReplayGainTagsFd, RestoreMetadataRegionFd:
FsyncGuard fsync_guard(fd);
TagLib::FileStream stream(fd, /*openReadOnly=*/false);
if (!stream.isOpen()) {
    // fdopen gagal — TagLib tidak mengambil ownership fd, kita harus tutup sendiri.
    // Jangan close(fd) di sini karena FsyncGuard sudah dup() dan akan menutup
    // dup_fd_ bukan fd asli. Perlu close fd asli sebelum return.
    // Karena FsyncGuard tidak tutup fd asli, lakukan manual:
    ::close(fd);
    return WriteResult::kPermissionFailure;
}
```

**Catatan:** `FsyncGuard(fd)` dibuat SEBELUM FileStream. FsyncGuard menyimpan `dup_fd_ = dup(fd)`. Ketika FsyncGuard destroyed, ia menutup `dup_fd_` (salinan), bukan fd asli. Jadi memanggil `::close(fd)` di `!stream.isOpen()` tidak double-close `dup_fd_` — keduanya adalah fd yang berbeda.

---

### [HIGH-2] Path-based write API adalah dead code — tidak pernah dipanggil dari live code path

**Severity:** High (tech debt + potential confusion)  
**Lokasi:**  
- `ReplayGainService.kt::writeReplayGain()` — baris 158–189  
- `ReplayGainService.kt::removeReplayGain()` — baris 195–199  
- `replaygain_jni.cpp::Java_..._nativeWriteReplayGainTags()` — baris 239–259  
- `replaygain_jni.cpp::Java_..._nativeRemoveReplayGainTags()` — baris 261–267  
- `tag_writer.cpp::WriteReplayGainTags()` + `RemoveReplayGainTags()` — baris 733–770

**Penjelasan:**

Terdapat dua jalur penulisan tag yang terpisah:

1. **Jalur fd-based (aktif):** `ReplayGainBridge.runFdMutation()` → `ReplayGainService.writeReplayGainFd()` → `nativeWriteReplayGainTagsFd()` → `WriteReplayGainTagsFd()`
2. **Jalur path-based (MATI):** `ReplayGainService.writeReplayGain(path, ...)` → `nativeWriteReplayGainTags()` → `WriteReplayGainTags(req)`

Jalur ke-2 sama sekali tidak dipanggil dari `ReplayGainBridge.writeReplayGain()` (satu-satunya titik masuk dari MainActivity). Fungsi path-based ini masih dikompilasi dan diekspor di `.so`, tetapi tidak ada kode Dart/Kotlin yang memanggilnya.

**Dampak:**
- Kode mati yang bisa membingungkan maintainer ke depan
- Jalur path-based menggunakan `WithCrashSafeWrite` (temp file + rename) yang bypass Scoped Storage — jika seseorang mengaktifkannya kembali tanpa memahami ini, bisa crash pada file yang tidak dimiliki app
- Menambah ukuran `.so` tanpa manfaat

**Solusi:**
- Jika tidak ada rencana untuk menggunakan path-based API lagi, hapus `ReplayGainService.writeReplayGain()`, `ReplayGainService.removeReplayGain()`, serta JNI + C++ counterpartnya
- Jika ingin dipertahankan untuk future use, beri annotasi `@Deprecated` dan komentar eksplisit di Kotlin

---

### [MEDIUM-1] `CopyFile()` tidak fsync sebelum `rename()` di crash-safe path-based write

**Severity:** Medium  
**Lokasi:** `tag_writer.cpp`, fungsi `CopyFile()` (baris 65–83) dan `WithCrashSafeWrite()` (baris 102–131)

**Penjelasan:**

```cpp
bool CopyFile(const std::string& src, const std::string& dst) {
    ...
    out << in.rdbuf();
    ...
    out.close();  // flush ke stdio buffer, tapi tidak fsync ke disk
    ...
    return true;
}
// Kemudian di WithCrashSafeWrite:
if (std::rename(temp_path.c_str(), original_path.c_str()) != 0) { ... }
```

`out.close()` di C++ `std::ofstream` memflush buffer `stdio`, tetapi tidak menjamin data sudah turun ke storage hardware. Jika sistem crash setelah `CopyFile` return tapi sebelum (atau tepat saat) `rename()`, file temp mungkin belum sepenuhnya tertulis ke disk — menghasilkan file audio yang corrupt menggantikan file asli.

**Dampak:** Korupsi file audio jika proses di-kill atau listrik mati tepat setelah `rename()` succeeds tapi data temp belum flushed. Skenario ini sangat jarang namun secara teori mungkin.

**Catatan:** Jalur ini saat ini adalah dead code (lihat HIGH-2), jadi risiko praktis = 0 sampai API path-based diaktifkan kembali.

**Solusi:**

```cpp
bool CopyFile(const std::string& src, const std::string& dst) {
    ...
    std::ofstream out(dst, std::ios::binary | std::ios::trunc);
    ...
    out << in.rdbuf();
    const bool write_ok = out.good();
    // Flush ke hardware sebelum mengandalkan rename atomic
    if (write_ok) {
        out.flush();
        const int fd = ::fileno(/* ... */);  // tidak langsung dari ofstream — gunakan open()+write() saja
    }
    out.close();
    ...
}
```

Atau lebih bersih: tulis ulang `CopyFile` menggunakan `open()` + `write()` + `fsync()` + `close()` berbasis POSIX secara langsung.

---

### [MEDIUM-2] `batch_scan_section.dart` menulis tag permanen tanpa peringatan eksplisit ke pengguna

**Severity:** Medium (UX/keamanan data pengguna)  
**Lokasi:** `lib/pages/settings_page/audio/batch_scan_section.dart`, baris 30

```dart
// Write tags automatically after scan — no manual confirmation needed.
unawaited(ReplayGainService.scanLibrary(songs, writeTags: true));
```

**Penjelasan:**

Tombol "Scan Library" langsung menulis tag ReplayGain secara permanen ke semua file audio tanpa dialog konfirmasi, tanpa toggle opt-in, dan tanpa menjelaskan ke pengguna bahwa file fisik akan dimodifikasi. Pengguna yang mengira "Scan" adalah operasi read-only akan terkejut mendapati file audio mereka berubah.

Risiko tambahan: jika proses di-kill di tengah scan batch (mis. OS kill untuk reclaim RAM), sebagian file sudah ditulis, sebagian belum — library tidak konsisten.

**Dampak:** File audio dimodifikasi secara permanen tanpa persetujuan eksplisit pengguna.

**Solusi:** Tambahkan toggle eksplisit "Tulis ke file" (default OFF) yang terpisah dari tombol scan, atau tampilkan dialog konfirmasi sebelum menulis tag, yang menjelaskan bahwa operasi ini akan memodifikasi metadata file audio secara permanen.

---

### [MEDIUM-3] Opus: dua format tag ditulis bersamaan — REPLAYGAIN_TRACK_GAIN dan R128_TRACK_GAIN dengan referensi berbeda

**Severity:** Medium  
**Lokasi:** `tag_writer.cpp`, fungsi `ApplyReplayGainFields()`, baris 294–311

```cpp
void ApplyReplayGainFields(TagLib::Ogg::XiphComment* comment, const WriteRequest& req,
                            bool is_opus) {
    SetXiphField(comment, "REPLAYGAIN_TRACK_GAIN", FormatGainDb(req.track_gain_db));
    // ...
    if (is_opus) {
        SetXiphField(comment, "R128_TRACK_GAIN", std::to_string(req.r128_track_q7_8));
```

**Penjelasan:**

Untuk file Opus, kedua field ditulis:
- `REPLAYGAIN_TRACK_GAIN` = gain relatif ke referensi **-18 LUFS** (format ReplayGain 2.0), ditulis sebagai string "+N.NN dB"
- `R128_TRACK_GAIN` = gain relatif ke referensi **-23 LUFS** (Opus RFC 7845), ditulis sebagai integer Q7.8

Keduanya adalah nilai yang **berbeda secara semantik** (beda 5 dB). Player yang hanya melihat `REPLAYGAIN_TRACK_GAIN` akan apply level yang berbeda dari player yang hanya melihat `R128_TRACK_GAIN`. Player yang menerapkan KEDUANYA akan over-normalize sebesar 5 dB.

**Dampak:** Inkonsistensi playback level tergantung player yang digunakan. App sendiri (Dart `_parseTrack`) memprioritaskan `replayGainTrackGain` → playback internal sudah benar. Tapi metadata yang dibuat bisa menyesatkan player lain.

Menurut Opus RFC 7845, `R128_TRACK_GAIN` adalah field **normative** untuk Opus. `REPLAYGAIN_TRACK_GAIN` di Opus adalah praktik umum tapi non-standar.

**Solusi (jika ingin strict RFC 7845):** Untuk file Opus, tulis `R128_TRACK_GAIN` saja dan hapus `REPLAYGAIN_TRACK_GAIN`. Jika ingin kompatibilitas luas (dual-tag), dokumentasikan keputusan ini secara eksplisit di komentar kode.

---

### [LOW-1] JNI local reference tidak di-DeleteLocalRef secara eksplisit di `PackSnapshot` dan `PackWriteEnvelope`

**Severity:** Low (informational)  
**Lokasi:** `replaygain_jni.cpp`, fungsi `PackSnapshot()` (baris 43–58) dan `PackWriteEnvelope()` (baris 98–118)

**Penjelasan:**

```cpp
jclass string_class = env->FindClass("java/lang/String");  // local ref, tidak di-delete
jclass object_class = env->FindClass("java/lang/Object");  // local ref, tidak di-delete
jclass integer_class = env->FindClass("java/lang/Integer"); // local ref, tidak di-delete
jobject code_obj = env->NewObject(...);                     // local ref, tidak di-delete
// Di PackSnapshot: 9x StdToJString() → 9 jstring local ref yang tidak di-delete
```

Semua local reference ini dibebaskan otomatis ketika JNI frame kembali ke Java. ART default frame = 512 slot. Dengan 9 string + beberapa class ref, total ~13 slot per call — jauh di bawah limit. **Tidak ada efek runtime** dalam kondisi normal.

**Risiko:** Jika fungsi ini dimodifikasi di masa depan untuk membuat lebih banyak objek tanpa awareness akan akumulasi ini, bisa mendekati limit.

**Solusi (opsional, best practice):**
```cpp
env->DeleteLocalRef(string_class);
env->DeleteLocalRef(code_obj);
// dst untuk setiap local ref yang tidak diperlukan lagi
```

---

### [LOW-2] Double write-access check per lagu di batch scan — overhead kecil

**Severity:** Low  
**Lokasi:** `MainActivity.kt` baris 653–684; `lib/services/replay_gain_service/service.dart::scanLibrary()`

**Penjelasan:**

Alur batch scan dengan `writeTags=true`:
1. `requestBatchWriteAccess(songIds)` → grant sudah diberikan untuk semua lagu
2. Per lagu: `writeReplayGain` MethodChannel call → MainActivity memanggil lagi `requestReplayGainWriteAccess(songId)` → `MediaStoreWriteGate.ensureWriteAccess()` → `tryOpenForWrite()` → `openFileDescriptor(uri, "rw")` → **langsung sukses** (grant sudah ada) → closed

Ini menyebabkan satu `openFileDescriptor("rw")` + langsung tutup yang tidak perlu per lagu. Overhead ~3–5 ms/lagu. Untuk library 500 lagu → overhead ~2–2.5 detik ekstra.

**Solusi (opsional):** Di `writeReplayGain` handler MainActivity, lewati `requestReplayGainWriteAccess` jika write access sudah dijamin oleh batch pre-authorization. Atau terima overhead ini sebagai trade-off untuk tetap menjaga logika yang simpel.

---

### [LOW-3] Silent failure di `openReplayGainWriteFd` — exception ditelan tanpa log

**Severity:** Low  
**Lokasi:** `MainActivity.kt`, fungsi `openReplayGainWriteFd()`, baris 883–892

```kotlin
private fun openReplayGainWriteFd(songId: Int): ParcelFileDescriptor? {
    val contentUri = ...
    return try {
        contentResolver.openFileDescriptor(contentUri, "rw")
    } catch (e: Exception) {
        null  // ← exception ditelan, tidak ada log
    }
}
```

**Penjelasan:** Jika fd tidak bisa dibuka (grant expired, file dihapus sementara scan, SecurityException), fungsi ini return null silently. `ReplayGainBridge.runFdMutation()` akan return `WRITE_ACCESS_DENIED` (yang di-log sebagai ERROR di Logcat). Namun exception aslinya hilang, mempersulit debugging.

**Solusi:**
```kotlin
} catch (e: Exception) {
    Log.w(TAG, "openReplayGainWriteFd($songId) failed: ${e.javaClass.simpleName} — ${e.message}")
    null
}
```

---

### [LOW-4] `ReplayGainError.WRITE_ACCESS_DENIED` posisi ordinal berdampingan dengan native enum

**Severity:** Low  
**Lokasi:** `ReplayGainModels.kt`, baris 30

```kotlin
enum class ReplayGainError {
    NONE,               // 0 = kOk
    ...
    VERIFICATION_FAILED, // 8 = kVerificationFailed (native appended)
    // Kotlin-only, no native ordinal:
    WRITE_ACCESS_DENIED; // 9
```

**Penjelasan:** `WRITE_ACCESS_DENIED` adalah ordinal 9. Komentar menyatakan ini "never passed to fromNative()". Namun tidak ada runtime guard — jika native suatu saat mengembalikan 9 karena bug atau refactor, `fromNative(9)` akan secara salah menghasilkan `WRITE_ACCESS_DENIED` bukan `UNKNOWN`. Tidak ada mekanisme proteksi.

**Solusi (minor):** Tambahkan guard eksplisit di `fromNative()`:
```kotlin
fun fromNative(code: Int): ReplayGainError {
    // Ordinal 9+ adalah Kotlin-only; native tidak pernah return >= 9
    if (code >= WRITE_ACCESS_DENIED.ordinal) return UNKNOWN
    return values().getOrElse(code) { UNKNOWN }
}
```

---

## 3. Android Scoped Storage — Penilaian

**Hasil: AMAN** untuk Android 10 dan 11+.

| Aspek | Status |
|---|---|
| Tidak menggunakan raw path untuk file yang tidak dimiliki app | ✅ fd-based API menggunakan `content://` URI |
| Tidak mengandalkan `MediaStore.Audio.Media.DATA` untuk write | ✅ Tidak ada penggunaan .DATA untuk write path |
| Menggunakan `MediaStore` dengan benar | ✅ `ContentUris.withAppendedId(EXTERNAL_CONTENT_URI, songId)` |
| Menggunakan `ParcelFileDescriptor` | ✅ `contentResolver.openFileDescriptor(uri, "rw")` + `detachFd()` |
| Android 11+: satu dialog untuk batch (bukan per file) | ✅ `MediaStore.createWriteRequest(resolver, uris)` |
| Android 10: fallback one-by-one dialog (platform limitation) | ✅ Ditangani dengan benar di `resolveLegacyBatch()` |
| Tidak meminta `WRITE_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` | ✅ Dikonfirmasi tidak diminta |
| Permission tidak bocor (dialog serialized) | ✅ `MediaStoreWriteGate.queue` + `dialogInFlight` guard |

---

## 4. JNI Audit

**Temuan per kategori:**

| Kategori | Status |
|---|---|
| Signature mismatch JNI ↔ Kotlin | ✅ Semua nama fungsi JNI (`Java_dev_wndavenz_music_replaygain_ReplayGainNative_native*`) cocok dengan Kotlin `object ReplayGainNative` |
| Null pointer check | ✅ `if (fd < 0)`, `if (elems == nullptr)`, `if (arr == nullptr)`, `if (analyzer == nullptr)` semua ada |
| Local reference leak | ⚠️ Ada (lihat LOW-1) — tidak menyebabkan masalah runtime pada ukuran saat ini |
| Global reference leak | ✅ Tidak ada global reference yang dibuat |
| File descriptor leak | ❌ **Ada pada path `!stream.isOpen()` — lihat HIGH-1** |
| Memory leak (EburAnalyzer handle) | ✅ Registry `g_registry` + `DestroyAnalyzer()` + `EburTrackSession.use{}` RAII |
| Unchecked exception dari JNI | ✅ Tidak ada C++ exception yang dibiarkan melintasi batas JNI |
| Exception propagation ke Java | ✅ JNI tidak memanggil `env->Throw*()` — error dikembalikan sebagai int ordinal |
| Thread safety analyzer registry | ✅ `std::mutex g_registry_mutex` melindungi semua akses ke `g_registry` |
| nativeComputeAlbumLoudness — UAF risk | ✅ Sudah diperbaiki dengan menahan mutex selama komputasi |
| GetShortArrayElements → ReleaseShortArrayElements | ✅ `JNI_ABORT` (tidak perlu copy-back karena read-only) |
| GetLongArrayElements → ReleaseLongArrayElements | ✅ `JNI_ABORT` sudah benar |
| fd ownership setelah detachFd | ✅ Kotlin tidak menutup PFD setelah detachFd; TagLib yang tutup fd via fclose() |

---

## 5. Native C/C++ Audit

**Temuan per kategori:**

| Kategori | Status |
|---|---|
| Memory leak | ✅ `std::string`, `std::vector`, `std::unique_ptr<EburAnalyzer>` — semua RAII |
| Use-after-free | ✅ Tidak ditemukan. EburAnalyzer pointer valid selama mutex held di nativeComputeAlbumLoudness |
| Double free | ✅ `std::remove()` dipakai untuk cleanup (bukan free); FsyncGuard destructor idempotent |
| Race condition | ✅ g_registry_mutex melindungi semua akses handle; tidak ada shared mutable state lain di tag writing path |
| Buffer overflow | ✅ `snprintf(buf, sizeof(buf), ...)` — buffer-bounded; PreadExact loop menggunakan size parameter |
| Integer overflow | ✅ `DetermineFlacRegionSize` menggunakan int64_t untuk offset; `syncsafe_size` max = ~256MB (syncsafe 28-bit) — reasonable |
| Undefined behavior | ✅ Tidak ditemukan. `std::max(0.0, peak)` mencegah NaN propagation ke snprintf |
| Dangling pointer | ✅ Tidak ada raw pointer ke heap-allocated data yang bisa dangle |
| Resource leak (fd) | ❌ **Lihat HIGH-1** — fd bocor jika TagLib::FileStream::isOpen() false |
| Error handling buruk | ✅ Semua return value TagLib `save()` dicek; `std::rename()` dicek |
| Null dereference | ✅ Semua pointer dicek sebelum dereference (`if (tag == nullptr)`, `if (comment == nullptr)`) |
| `pread()` partial read | ✅ `PreadExact()` loop sampai `total == len` atau error |

---

## 6. TagLib Audit

**Temuan per kategori:**

| Aspek | Status |
|---|---|
| File open | ✅ `file.isValid()` dicek setelah setiap konstruksi TagLib::File |
| fd handling | ⚠️ **Lihat HIGH-1** — jika fdopen internal TagLib gagal, fd bocor |
| save() return value | ✅ Semua `file.save()` di-check; return kWriteFailure jika false |
| flush / fsync | ✅ FsyncGuard memanggil `fsync(dup_fd_)` setelah setiap save() di fd path |
| close() | ✅ TagLib menutup fd melalui `fclose()` saat FileStream destroyed (jika fdopen berhasil) |
| Cleanup jika gagal | ✅ temp file dihapus via `std::remove()` di semua failure path; RegionBackup restoration di fd path |
| Rollback jika gagal | ✅ Path-based: atomic rename — jika rename gagal, temp dihapus dan original utuh; Fd-based: exact-region restore via `stream.insert()` |
| File corrupt jika proses mati di tengah save() | ⚠️ Residual risk yang **disadari dan didokumentasikan** di tag_writer.h. Tidak bisa dihindari tanpa MANAGE_EXTERNAL_STORAGE atau full-file copy untuk content:// fds. Trade-off yang diterima secara sadar |
| TagLib versi | ✅ v2.3 (pinned di CMakeLists.txt) — cukup stabil untuk API yang digunakan |

---

## 7. Metadata Validation — Format Value

| Format | Field | Format Value | Spesifikasi | Status |
|---|---|---|---|---|
| MP3 (ID3v2) | `REPLAYGAIN_TRACK_GAIN` | `"+N.NN dB"` (snprintf `%+.2f dB`) | TXXX frame, nilai konvensional dengan tanda dan unit | ✅ Benar |
| MP3 (ID3v2) | `REPLAYGAIN_TRACK_PEAK` | `"0.NNNNNN"` (snprintf `%.6f`) | Linear peak, 6 desimal, tanpa unit | ✅ Benar |
| MP3 (ID3v2) | `REPLAYGAIN_ALBUM_GAIN` | `"+N.NN dB"` | Sama dengan track gain | ✅ Benar |
| MP3 (ID3v2) | `REPLAYGAIN_ALBUM_PEAK` | `"0.NNNNNN"` | Sama dengan track peak | ✅ Benar |
| MP3 (ID3v2) | Typo field name? | `"REPLAYGAIN_TRACK_GAIN"` | Standard nama yang benar | ✅ Tidak ada typo |
| FLAC | `REPLAYGAIN_TRACK_GAIN` | Xiph comment, format sama | Vorbis Comment, case-insensitive per spec | ✅ Benar |
| Ogg Vorbis | `REPLAYGAIN_TRACK_GAIN` | Xiph comment | Sama | ✅ Benar |
| Ogg Opus | `R128_TRACK_GAIN` | `"N"` integer (Q7.8, 256 = 1 dB, ref -23 LUFS) | RFC 7845 §5.2.1 | ✅ Benar |
| Ogg Opus | `R128_ALBUM_GAIN` | `"N"` integer (Q7.8) | RFC 7845 | ✅ Benar |
| Encoding | Semua string | UTF-8 | TagLib `String::UTF8` | ✅ Benar |
| ITUNNORM removal (MP3) | `"ITUNNORM"` dan `"ITUN NORM"` | Dihapus saat removeReplayGain | Dua ejaan yang ditemukan di alam liar | ✅ Ditangani keduanya |
| Duplikat TXXX frame | Dicek + dibersihkan sebelum tulis | `RemoveTxxx` iterasi seluruh frame list | Mencegah akumulasi frame duplikat | ✅ Idempotent |

---

## 8. Error Handling

| Skenario | Penanganan | Status |
|---|---|---|
| Permission denied (fd write) | `WriteResult::kPermissionFailure` → `ReplayGainError.PERMISSION_FAILURE` | ✅ |
| Save gagal (TagLib) | `WriteResult::kWriteFailure` → dipropagasi ke Dart | ✅ |
| Metadata corrupt (file.isValid() false) | `WriteResult::kCorruptedFile` | ✅ |
| File tidak ditemukan | `TagLib::FileStream::isOpen() false` → `kPermissionFailure` | ⚠️ Dikembalikan sebagai PermissionFailure bukan FileNotFound — kurang presisi, tapi tidak silent |
| ParcelFileDescriptor gagal dibuka | `openReplayGainWriteFd()` return null → `WRITE_ACCESS_DENIED` | ✅ (tapi exception ditelan tanpa log — LOW-3) |
| JNI exception | Tidak ada C++ exception yang melewati JNI boundary; semua error sebagai int return code | ✅ |
| Verification gagal | `VERIFICATION_FAILED` → attempt rollback exact region | ✅ |
| Rollback gagal setelah verify gagal | Log ERROR + return `VERIFICATION_FAILED` | ✅ |
| User decline dialog | `WRITE_ACCESS_DENIED` → `result.success({"success": false, "error": "WRITE_ACCESS_DENIED"})` | ✅ |
| Metadata region tidak bisa ditentukan | `WriteResult::kUnknown` → write dibatalkan, file tidak disentuh | ✅ |
| Silent failure | Tidak ada | ✅ Semua failure path menghasilkan log Warning atau Error |

---

## 9. Threading

| Aspek | Status |
|---|---|
| Scan tidak di UI thread | ✅ `replayGainScanExecutor` (background) |
| Write tidak di UI thread | ✅ `metadataExecutor` (background, single-thread) |
| Concurrent write ke file yang sama | ✅ metadataExecutor adalah serialized single-thread executor; dua lagu berbeda bisa berjalan berurutan tapi tidak paralel pada file yang sama |
| Write-access grant request di main thread | ✅ `MediaStoreWriteGate` didesain untuk main thread; drainQueue() tidak thread-safe intentionally |
| openFd() dari background thread | ✅ ContentResolver aman dari background thread |
| Dart scanLibrary — guard reentrancy | ✅ `if (scanProgress.value.running) return` |
| `_cancelRequested` flag | ✅ Dart single-threaded event loop, tidak ada data race |
| EburAnalyzer registry | ✅ `std::mutex g_registry_mutex` untuk semua akses |
| nativeComputeAlbumLoudness UAF fix | ✅ Mutex held selama komputasi libebur128 |

---

## 10. Logging

| Aspek | Status |
|---|---|
| Informatif | ✅ Error code + song title/path di semua failure path |
| Tidak spam | ✅ Verbose log hanya saat `LogService.verbose()` level |
| Mudah debug | ✅ Error code berbentuk string (`ReplayGainError.name`) dikembalikan ke Dart |
| Tidak bocorkan info sensitif | ✅ Hanya path file audio (bukan data pribadi pengguna) yang di-log |
| Exception di `openReplayGainWriteFd` ditelan | ⚠️ Lihat LOW-3 |

---

## 11. Performance

| Potensi Bottleneck | Penilaian |
|---|---|
| Double `openFileDescriptor` per lagu di batch scan (write access check redundan) | ⚠️ ~3–5 ms/lagu overhead (lihat LOW-2) |
| `Future.wait` 2 scan paralel per chunk | ✅ Sesuai kapasitas hardware MediaCodec Snapdragon 730 |
| `DetermineMetadataRegionSize` menggunakan pread (tidak mempengaruhi posisi fd TagLib) | ✅ Tidak ada seek conflict |
| `g_registry_mutex` held selama `ComputeAlbumLoudness` | ✅ Komputasi sub-millisecond, tidak masalah |
| RegionBackup: backup seluruh metadata region ke heap string | ✅ Benar; untuk file dengan art besar (2MB) backup = 2MB di heap — sekali per write, langsung dibebaskan |
| CopyFile (path-based, dead code) | Alokasi full-file copy di heap via rdbuf — tidak efisien tapi dead code saat ini |
| SharedPreferences write per lagu di Dart | ✅ Paralel via `Future.wait()` (3 key per lagu) |

---

## 12. Security

| Aspek | Status |
|---|---|
| Arbitrary path access | ✅ fd-based path hanya menerima fd dari MediaStore — tidak bisa dimanipulasi ke arbitrary path |
| Path traversal | ✅ Tidak menerima path arbitrary dari Dart untuk operasi write — hanya `songId` yang digunakan untuk membangun `content://` URI |
| Invalid file descriptor | ✅ `if (fd < 0) return WriteResult::kInvalidArgument` |
| Unchecked input dari Dart | ✅ `trackGainDb`, `trackPeakLinear`, dll dibaca sebagai `jdouble` — tidak ada injection vector |
| Malformed metadata | ✅ `file.isValid()` check setelah open; abort dengan `kCorruptedFile` |
| Injection melalui metadata | ✅ Semua nilai di-format melalui `snprintf`/`std::to_string` — tidak ada string concatenation ke tag yang bisa di-inject |
| Tag name injection (TXXX description) | ✅ Description adalah literal constant (`"REPLAYGAIN_TRACK_GAIN"` dst), bukan dari input |
| Temp file (path-based, dead code) | ⚠️ Nama temp file adalah `path + ".rgtmp"` — predictable. Tidak relevan karena dead code, dan path-based API hanya dipakai untuk file app-owned |

---

## 13. Production Readiness

### Apakah fitur ReplayGain Write Tag sudah production-ready?

**Hampir — dengan satu perbaikan wajib sebelum release.**

---

### Blocker sebelum release

| # | Issue | Lokasi | Fix |
|---|---|---|---|
| 1 | **Fd leak ketika TagLib::FileStream gagal open** (HIGH-1) | `tag_writer.cpp` — 3 fungsi | Tambahkan `::close(fd)` sebelum `return kPermissionFailure` di path `!stream.isOpen()` |

---

### Yang masih kurang / risiko tersisa

| # | Issue | Severity | Keterangan |
|---|---|---|---|
| 2 | Tags ditulis tanpa peringatan ke pengguna (MEDIUM-2) | Medium | UX — pengguna harus tahu file dimodifikasi |
| 3 | Opus dual-tag REPLAYGAIN + R128 (MEDIUM-3) | Medium | Desain, bukan bug; tapi bisa konfus player lain |
| 4 | Path-based API dead code masih ada (HIGH-2) | Medium | Cleanup tech debt |
| 5 | Residual crash-window untuk Scoped Storage fd (by design) | Accepted | Didokumentasikan di tag_writer.h; tidak bisa dihindari tanpa MANAGE_EXTERNAL_STORAGE |

---

### Yang sudah baik dan production-ready ✅

- **Crash-safe write:** Atomic rename untuk path-based; exact-region backup + verify + rollback untuk fd-based
- **Post-write verification:** Read-back comparison setelah setiap write, bukan "trust TagLib and hope"
- **Byte-exact rollback:** `DetermineMetadataRegionSize` + `stream.insert()` — restore tepat ukuran region, bukan fixed-size guess
- **Scoped Storage compliance:** Semua write via MediaStore content:// URI; tidak meminta WRITE_EXTERNAL_STORAGE
- **Satu dialog untuk batch:** `MediaStore.createWriteRequest()` batch grant (Android 11+)
- **Thread safety:** metadataExecutor serialized; analyzer registry mutex; Dart reentrancy guard
- **Idempotent write:** RemoveTxxx/removeFields sebelum set — re-scan tidak akumulasi duplicate tags
- **Format correctness:** ID3v2 TXXX untuk MP3, Vorbis Comment untuk FLAC/Ogg, R128 Q7.8 untuk Opus
- **Audio tidak di-re-encode:** TagLib hanya menulis ulang metadata region, audio frames tidak disentuh
- **Semua metadata lain dipreservasi:** cover art, lyrics, ISRC, disc/track number tidak terganggu
- **Error tidak silent:** Semua failure path menghasilkan error code yang dipropagasi ke Dart

---

*End of audit report.*
