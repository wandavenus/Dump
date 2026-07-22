# Audit Native C/C++ — Production Readiness
**Tanggal:** 2026-07-20  
**Auditor:** Manual review (setara senior C++ engineer)  
**Scope:** `android/app/src/main/cpp/**` — 2.206 baris, 10 file

---

## Cakupan File yang Diaudit

| File | Baris | Peran |
|---|---|---|
| `replaygain/tag_writer.cpp` | 538 | TagLib fd-based write / remove / verify / restore |
| `replaygain/tag_writer.h` | 188 | API declarations + struct definitions |
| `replaygain/metadata_region.cpp` | 210 | Binary parser: MP3/FLAC/Ogg metadata region sizing |
| `replaygain/metadata_region.h` | 54 | DetermineMetadataRegionSize / ReadRegion API |
| `replaygain/replaygain_jni.cpp` | 320 | JNI bridge: EburAnalyzer + tag-write entry points |
| `replaygain/ebur128_analyzer.cpp` | 113 | libebur128 wrapper, LUFS/RG2.0 computation |
| `replaygain/ebur128_analyzer.h` | 85 | EburAnalyzer class declaration |
| `replaygain/jni_common.h` | 50 | JString helpers + ErrorCode enum |
| `stretch/stretch_jni.cpp` | 485 | Signalsmith Stretch JNI bridge (pitch/time) |
| `CMakeLists.txt` | 163 | Build config: libebur128, TagLib, Signalsmith |

> **Catatan:** `native_audio_runtime/` (DSP pipeline: compressor, limiter, PEQ, NEON, dll.)
> **TIDAK** ada dalam direktori ini dan **TIDAK** termasuk dalam scope audit ini.
> Jika diperlukan, perlu audit terpisah untuk library itu.

---

---

# TEMUAN AUDIT

---

## Temuan #1

### Severity: **HIGH**

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/metadata_region.cpp`
- **Function:** `DetermineMp3RegionSize`, `DetermineFlacRegionSize`, `DetermineOggHeaderRegionSize` → dieksekusi lewat `ReadRegion`
- **Line:** 27–49 (MP3), 54–77 (FLAC), 123–181 (Ogg), 200–208 (ReadRegion)

### Penjelasan

`DetermineMetadataRegionSize` mengembalikan nilai `int64_t` yang kemudian dipakai oleh `ReadRegion` sebagai argumen ke `std::string::resize()` tanpa batas atas sama sekali. Tiga parser format dapat mengembalikan nilai yang sangat besar dari file yang malformed:

**MP3 (ID3v2):**
```cpp
// DetermineMp3RegionSize, line 43-49
const int64_t syncsafe_size =
    (static_cast<int64_t>(hdr[6]) << 21) | (static_cast<int64_t>(hdr[7]) << 14) |
    (static_cast<int64_t>(hdr[8]) << 7) | static_cast<int64_t>(hdr[9]);
int64_t total = 10 + syncsafe_size;
if (has_footer) total += 10;
return total;
```
Syncsafe integer ID3v2 adalah 28-bit. Nilai maksimum: 2²⁸ − 1 = 268.435.455 byte (~256 MB). Tidak ada pemeriksaan bahwa nilai ini masuk akal. File dengan header ID3v2 yang menyatakan tag 256 MB → `ReadRegion` mencoba mengalokasikan 256 MB.

**FLAC:**
```cpp
// DetermineFlacRegionSize, line 70-74
const int64_t block_len = (static_cast<int64_t>(bh[1]) << 16) |
                           (static_cast<int64_t>(bh[2]) << 8) |
                           static_cast<int64_t>(bh[3]);
offset += 4 + block_len;
if (is_last) return offset;
```
`block_len` adalah 24-bit (maksimum 16.777.215 per block). Satu block metadata dengan `is_last=true` dan `block_len=16.777.215` → mengembalikan 4 + 4 + 16.777.215 = 16.777.223 byte (~16 MB). Rantai 4.096 block (guard limit) masing-masing 16 MB → secara teori hingga 68,7 GB sebelum PreadExact gagal karena EOF. Nilai yang dikembalikan dipakai langsung oleh ReadRegion tanpa capping.

**Ogg (Vorbis / Opus):**
```cpp
// DetermineOggHeaderRegionSize: page_total_size per halaman maksimum 65.307 byte,
// guard limit 200.000 halaman → total offset bisa mencapai ~12,7 GB
return page->page_start + page->page_total_size;
```

**ReadRegion tanpa batas:**
```cpp
// ReadRegion, line 206-207
out->resize(static_cast<size_t>(size));  // ← TIDAK ADA batas atas
return PreadExact(fd, 0, out->data(), static_cast<size_t>(size));
```

**Bagaimana bug ini terjadi:**
File audio yang corrupt (download gagal, bit error, tool tagging lain yang buggy) atau file yang sengaja dibuat untuk mengeksploitasi ini bisa menyebabkan alokasi ratusan MB. Android OOM killer akan membunuh proses aplikasi.

**Kapan bug ini muncul:**
Setiap kali `writeReplayGain` atau `removeReplayGain` dipanggil pada file dengan header metadata yang corrupt atau oversized.

**Dampak:**
- Process kill (OOM) → app crash
- Tidak ada crash log yang bermakna di Kotlin (OOM killer membunuh proses secara paksa)
- Kasus ekstrem: alokasi gigabyte pada file FLAC atau Ogg yang sangat malformed → SIGKILL dari kernel

**Mengapa HIGH:**
Dapat terjadi di production dengan file audio yang corrupt (skenario umum). Dampaknya adalah crash total aplikasi (OOM kill), bukan hanya kegagalan satu operasi.

### Solusi

**Patch yang direkomendasikan — tambahkan batas atas di `ReadRegion`:**

```cpp
// metadata_region.cpp, sebelum out->resize()

// Sanity cap: tag regions di atas 64 MB tidak akan pernah legitimate.
// FLAC bisa memiliki banyak embedded artwork, tapi 64 MB sudah lebih dari cukup.
// Jika diklaim lebih besar, reject sebagai malformed.
constexpr int64_t kMaxSafeRegionBytes = 64LL * 1024 * 1024;  // 64 MB

bool ReadRegion(int fd, int64_t size, std::string* out) {
    if (size < 0 || out == nullptr) return false;
    if (size == 0) { out->clear(); return true; }
    if (size > kMaxSafeRegionBytes) return false;  // ← TAMBAHKAN INI
    out->resize(static_cast<size_t>(size));
    return PreadExact(fd, 0, out->data(), static_cast<size_t>(size));
}
```

Caller (`BackupRegion`) sudah memperlakukan `ReadRegion` yang mengembalikan false sebagai `kWriteFailure` → write dibatalkan dengan benar. Tidak ada perubahan lain diperlukan.

**Trade-off:** Cap 64 MB menolak file dengan embedded artwork gabungan yang sangat besar (misalnya 20 gambar × 3 MB). Jika ini menjadi masalah praktis, cap bisa dinaikkan ke 128 MB. Untuk music player normal, 64 MB adalah batas yang aman dan konservatif.

---

## Temuan #2

### Severity: **MEDIUM**

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.cpp`
- **Function:** `RestoreMetadataRegionFd`
- **Line:** 526–534

### Penjelasan

```cpp
// RestoreMetadataRegionFd, line 526-534
const TagLib::ByteVector data(backup.bytes.data(),
                               static_cast<unsigned int>(backup.bytes.size()));
stream.insert(data, /*start=*/0, /*replace=*/static_cast<size_t>(*current_size));
fsync_guard.Sync();
return WriteResult::kOk;  // ← selalu kOk
```

`TagLib::FileStream::insert()` adalah metode virtual yang mengembalikan `void` — tidak ada return code, tidak ada exception. Secara internal, TagLib menandai error lewat flag private `d->error`, tetapi tidak ada public API untuk membaca flag ini di versi yang digunakan.

Jika I/O gagal selama `insert()` (misalnya: storage full, hardware error, kernel interrupt), operasi restore selesai tanpa deteksi kegagalan. Fungsi mengembalikan `kOk`. Kotlin percaya bahwa file berhasil dipulihkan padahal kondisi file tidak dapat diprediksi.

**Bagaimana bug ini terjadi:**
Skenario: write primer berhasil sebagian (TagLib sempat memodifikasi file), verification gagal (kVerificationFailed), Kotlin membuka write fd baru dan memanggil `RestoreMetadataRegionFd` untuk rollback. Jika storage kehabisan ruang saat insert, rollback diam-diam gagal. Kotlin menerima `kOk` dan tidak mencoba fallback lain, meninggalkan file dalam kondisi tidak konsisten — mungkin dengan tag yang sebagian tertimpa.

**Kapan bug ini muncul:**
Skenario yang tidak umum tetapi nyata: device storage hampir penuh saat user menulis ReplayGain tags ke banyak file sekaligus.

**Dampak:**
- File audio bisa memiliki metadata yang corrupt setelah "restoration" yang diam-diam gagal
- Tidak ada error yang dilaporkan ke user
- Severity diturunkan ke MEDIUM karena: (a) `RestoreMetadataRegionFd` hanya dipanggil saat verification gagal (sudah merupakan kasus error), (b) ini adalah keterbatasan TagLib API, bukan logika yang salah

**Mengapa MEDIUM:**
Bug nyata, dampak berupa korupsi data. Namun kejadiannya membutuhkan dua kondisi bersamaan (write gagal DAN storage penuh saat restore), dan alternatif perbaikannya terbatas karena kendala TagLib API.

### Solusi

**Solusi parsial — verifikasi read-back setelah insert:**

```cpp
WriteResult RestoreMetadataRegionFd(int fd, TagFormat format, const RegionBackup& backup) {
    // ... (kode existing sampai stream.insert())
    stream.insert(data, 0, static_cast<size_t>(*current_size));
    fsync_guard.Sync();

    // Partial verification: baca kembali N byte pertama dari region
    // dan bandingkan dengan backup. Jika tidak cocok, insert kemungkinan gagal.
    if (!backup.bytes.empty()) {
        constexpr size_t kVerifyBytes = 16;
        const size_t to_check = std::min(backup.bytes.size(), kVerifyBytes);
        char verify_buf[kVerifyBytes];
        if (::pread(fd, verify_buf, to_check, 0) == static_cast<ssize_t>(to_check)) {
            if (std::memcmp(verify_buf, backup.bytes.data(), to_check) != 0) {
                return WriteResult::kWriteFailure;  // restore gagal
            }
        }
    }
    return WriteResult::kOk;
}
```

**Catatan trade-off:** Verifikasi ini tidak 100% — hanya memeriksa 16 byte pertama. Namun ini mendeteksi kasus gagal total (insert tidak menulis apapun). Solusi yang lebih kuat memerlukan perubahan pada TagLib internals yang di luar scope ini.

**Solusi alternatif (arsitektur):** Kotlin bisa mengimplementasikan verifikasi independen setelah restore dengan membuka read fd dan memeriksa beberapa field tag yang diketahui dari backup. Ini lebih handal tetapi membutuhkan perubahan di layer Kotlin.

---

## Temuan #3

### Severity: **LOW**

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/replaygain_jni.cpp`
- **Function:** `PackSnapshot`, `PackWriteEnvelope`
- **Line:** 43–58 (PackSnapshot), 98–119 (PackWriteEnvelope)

### Penjelasan

**PackSnapshot (line 53–55):**
```cpp
for (int i = 0; i < kSnapshotFieldCount; i++) {
    if (fields[i]->has_value()) {
        env->SetObjectArrayElement(arr, i, replaygain::StdToJString(env, **fields[i]));
        // ↑ jstring local ref dari NewStringUTF() TIDAK di-DeleteLocalRef()
    }
}
```
`StdToJString` memanggil `env->NewStringUTF()` yang menghasilkan local reference baru. Setelah `SetObjectArrayElement`, array sudah menyimpan referensinya sendiri. Local ref asli seharusnya dihapus dengan `DeleteLocalRef` tapi tidak pernah dilakukan. 9 ref per panggilan.

**PackWriteEnvelope (line 100–117):**
Lima local ref tambahan tidak dihapus:
- `object_class` dari `FindClass("java/lang/Object")`
- `integer_class` dari `FindClass("java/lang/Integer")`
- `code_obj` dari `NewObject(...)` setelah `SetObjectArrayElement`
- Return value dari `PackSnapshot(env, snap)` setelah `SetObjectArrayElement`
- `region_bytes` dari `NewByteArray(...)` setelah `SetObjectArrayElement`

**Bagaimana bug ini terjadi:**
Setiap pemanggilan `nativeWriteReplayGainTagsFd` atau `nativeRemoveReplayGainTagsFd` bocorkan ~14 local ref dalam satu JNI frame.

**Kapan bug ini muncul:**
Tidak pernah crash dalam praktik. Android Runtime (ART) menyediakan 512 slot local ref per JNI method invocation. 14 ref << 512. JNI spec mewajibkan cleanup, tapi crash hanya terjadi jika tabel overflow (>512).

**Dampak:**
JNI spec violation. Tidak ada crash yang realistis pada codebase ini. Namun: jika di masa depan kode direfactor dalam PushLocalFrame dengan kapasitas kecil, atau dipanggil dari konteks yang sudah memakai banyak ref, ini bisa menjadi masalah.

**Mengapa LOW:**
Melanggar JNI spec tetapi tidak menimbulkan crash dalam kondisi produksi nyata.

### Solusi

**Patch untuk PackSnapshot:**
```cpp
for (int i = 0; i < kSnapshotFieldCount; i++) {
    if (fields[i]->has_value()) {
        jstring jstr = replaygain::StdToJString(env, **fields[i]);
        env->SetObjectArrayElement(arr, i, jstr);
        env->DeleteLocalRef(jstr);  // ← TAMBAHKAN
    }
}
```

**Patch untuk PackWriteEnvelope:**
```cpp
jclass object_class = env->FindClass("java/lang/Object");
jobjectArray envelope = env->NewObjectArray(3, object_class, nullptr);
env->DeleteLocalRef(object_class);  // ← TAMBAHKAN

jclass integer_class = env->FindClass("java/lang/Integer");
jmethodID ctor = env->GetMethodID(integer_class, "<init>", "(I)V");
jobject code_obj = env->NewObject(integer_class, ctor, static_cast<jint>(result));
env->DeleteLocalRef(integer_class);  // ← TAMBAHKAN
env->SetObjectArrayElement(envelope, 0, code_obj);
env->DeleteLocalRef(code_obj);  // ← TAMBAHKAN

if (include_payload) {
    jobjectArray snap_arr = PackSnapshot(env, snap);
    env->SetObjectArrayElement(envelope, 1, snap_arr);
    env->DeleteLocalRef(snap_arr);  // ← TAMBAHKAN

    jbyteArray region_bytes = env->NewByteArray(...);
    // ... fill bytes ...
    env->SetObjectArrayElement(envelope, 2, region_bytes);
    env->DeleteLocalRef(region_bytes);  // ← TAMBAHKAN
}
```

---

## Temuan #4

### Severity: **LOW**

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.cpp`
- **Class:** `FsyncGuard`
- **Line:** 222

### Penjelasan

```cpp
explicit FsyncGuard(int original_fd) : dup_fd_(::dup(original_fd)) {}
```

`::dup()` bisa gagal dan mengembalikan -1 (error: EMFILE — terlalu banyak fd terbuka). Dalam kasus ini, `dup_fd_ = -1`. `Sync()` dan destructor memeriksa `dup_fd_ >= 0` sebelum bertindak, jadi tidak ada crash. Namun:

1. `fsync` tidak pernah dipanggil untuk write ini.
2. Tidak ada pelaporan kegagalan ke caller.
3. Window crash (file dalam keadaan tidak fsync'd) melebar antara write TagLib dan eventual OS flush.

**Bagaimana bug ini terjadi:**
Kegagalan `dup()` sangat jarang di Android untuk sebuah music player (fd limit default ~1024), tetapi bisa terjadi jika ada fd leak di tempat lain dalam aplikasi.

**Dampak:**
Jika proses mati setelah TagLib save() tapi sebelum kernel flush data ke disk (dalam window antara detik-detik setelah save), data tag tidak terjamin tertulis ke disk. Praktisnya, ini berarti potensi tag corruption setelah phone mati mendadak. Kecil kemungkinannya tapi tidak nol.

**Mengapa LOW:**
Kegagalan dup() jarang terjadi, dan fsync sudah didokumentasikan sebagai "best-effort" dalam komentar kode. Juga verifikasi lewat read-back tetap berjalan — hanya durabilitas disk yang berkurang.

### Solusi

```cpp
explicit FsyncGuard(int original_fd) : dup_fd_(::dup(original_fd)) {
    if (dup_fd_ < 0) {
        // dup() failed (EMFILE?) — fsync won't be possible.
        // Log via __android_log_print if logging is wired here; for now,
        // the Sync() no-op is intentional and documented.
        __android_log_print(ANDROID_LOG_WARN, "TagWriterNative",
            "FsyncGuard: dup(%d) failed errno=%d — fsync will be skipped", original_fd, errno);
    }
}
```

Ini tidak memperbaiki kegagalan fsync (tidak mungkin tanpa fd), tapi setidaknya kegagalan tercatat di Logcat untuk diagnosis.

---

## Temuan #5

### Severity: **LOW**

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/replaygain_jni.cpp`
- **Function:** `Java_dev_wndavenz_music_replaygain_ReplayGainNative_nativeAddFramesShort`
- **Line:** 164–173

### Penjelasan

```cpp
JNIEXPORT jboolean JNICALL
Java_..._nativeAddFramesShort(
    JNIEnv* env, jobject /*thiz*/, jlong handle, jshortArray buf, jint frame_count) {
    EburAnalyzer* analyzer = LookupAnalyzer(handle);
    if (analyzer == nullptr || frame_count <= 0) return JNI_FALSE;

    jshort* elems = env->GetShortArrayElements(buf, nullptr);
    if (elems == nullptr) return JNI_FALSE;
    const bool ok = analyzer->AddFramesShort(
        reinterpret_cast<const int16_t*>(elems),
        static_cast<size_t>(frame_count));  // ← frame_count diteruskan ke libebur128
    env->ReleaseShortArrayElements(buf, elems, JNI_ABORT);
```

`frame_count` adalah jumlah frames (samples-per-channel). libebur128 mengakses `buf[0..frame_count*channels-1]`. Ukuran actual array adalah `env->GetArrayLength(buf)` shorts. Jika Kotlin meneruskan `frame_count > GetArrayLength(buf) / channels`, `ebur128_add_frames_short` membaca di luar batas array yang dipinned → out-of-bounds read → UB / kemungkinan crash.

**Kapan bug ini muncul:**
Hanya jika Kotlin meneruskan `frame_count` yang salah. Dalam implementasi current (EburTrackSession.kt), buffer dialokasikan persis untuk `frame_count * channels` samples, jadi tidak akan terjadi dengan kode Kotlin yang benar.

**Dampak:**
Tidak praktis terjadi di production dengan Kotlin caller yang benar. Namun jika ada refactor di sisi Kotlin yang salah menghitung buffer, ini bisa menyebabkan crash atau silent data corruption pada libebur128.

**Mengapa LOW:**
Trusted caller (Kotlin side); tidak realistic terjadi di production.

### Solusi

```cpp
jshort* elems = env->GetShortArrayElements(buf, nullptr);
if (elems == nullptr) return JNI_FALSE;

// Validate that the array is large enough for frame_count * channels.
// channels is stored inside the analyzer; surface it for validation.
const jsize array_len = env->GetArrayLength(buf);
// analyzer->channels() needs to be exposed, or we validate that at least
// frame_count short values exist (conservative: frame_count * 1 channel minimum).
// A tighter check requires exposing channel count from EburAnalyzer.
if (array_len < frame_count) {
    env->ReleaseShortArrayElements(buf, elems, JNI_ABORT);
    return JNI_FALSE;
}
```

Untuk validasi yang lebih ketat, expose `channels_` dari `EburAnalyzer` dan periksa `array_len >= frame_count * channels`.

---

## Temuan #6

### Severity: **LOW**

### Lokasi
- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp`
- **Function:** `Java_..._nativeProcess`
- **Line:** 297–298

### Penjelasan

```cpp
const auto now = std::chrono::steady_clock::now();
const bool shouldLog = (now - h->lastProcessLogTime) >= kProcessLogInterval;
```

`std::chrono::steady_clock::now()` dipanggil **setiap kali** `nativeProcess()` dipanggil, yaitu di setiap audio rendering callback ExoPlayer (~10-20 ms interval untuk 44.1kHz dengan buffer 512 frame). Di Linux/Android, `steady_clock::now()` diimplementasikan via VDSO (`clock_gettime(CLOCK_MONOTONIC)`) — biasanya < 1 μs. Namun:

1. VDSO adalah system call yang bisa stall jika clock driver bermasalah atau di bawah load berat.
2. Ini adalah overhead yang tidak diperlukan pada setiap audio callback, sebagian besar panggilan akan memiliki `shouldLog = false` dan tidak melakukan logging sama sekali.

**Dampak:**
Latency audio yang sedikit meningkat pada setiap callback (~0.5–2 μs). Pada kondisi normal ini tidak terdengar. Pada kondisi stress (CPU load tinggi, thermal throttling), stall VDSO bisa menjadi millisecond.

**Mengapa LOW:**
VDSO sangat cepat di Android, dan delay kecil ini tidak realistis menyebabkan glitch audio pada hardware target (Snapdragon 730).

### Solusi

**Opsi 1 (minimal impact):** Hitung `now` hanya jika diperlukan — gunakan counter frame sebagai proxy throttle:

```cpp
h->processCallCount++;
const bool shouldLog = (h->processCallCount % kLogEveryNCalls == 0);
```

Dengan `kLogEveryNCalls = 100` (≈ 1–2 detik pada 44.1kHz), clock tidak perlu dibaca sama sekali. Ini juga lebih deterministik.

**Opsi 2 (current throttle tetap, kurangi overhead):** Pindahkan clock read ke dalam blok `try`, setelah operasi kritis selesai — sehingga scheduling decision dibuat sekali per blok, bukan sebagai gating condition.

---

## Temuan #7

### Severity: **LOW**

### Lokasi
- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp`
- **Function:** `StretchHandle::ensureCapacity` dipanggil dari `nativeProcess`, `nativePrime`, `nativeFlush`
- **Line:** 159–172, dipanggil dari 301, 426, 469

### Penjelasan

```cpp
void ensureCapacity(int inFrames, int outFrames) {
    ...
    if (inFlat.size() < inNeeded) inFlat.resize(inNeeded);    // ← heap alloc
    if (outFlat.size() < outNeeded) outFlat.resize(outNeeded); // ← heap alloc
    ...
}
```

`std::vector::resize()` mengalokasikan heap jika kapasitas tidak cukup. `ensureCapacity` dipanggil dari `nativeProcess`, yang berjalan di audio rendering thread ExoPlayer — sebuah realtime-class thread yang secara ideal tidak boleh melakukan heap allocation.

**Kapan bug ini muncul:**
Hanya selama "warmup" (beberapa panggilan pertama setelah `nativeCreate`). Setelah buffer cukup besar untuk buffer size maksimum yang diterima, `resize` tidak mengalokasikan lagi (grow-only pattern).

**Dampak:**
Potensi audio glitch pada N panggilan pertama setelah handle dibuat (biasanya < 5 panggilan). Setelah warmup, tidak ada alokasi di audio thread. Ini adalah trade-off yang sudah didokumentasikan di komentar kode.

**Mengapa LOW:**
Sudah didokumentasikan sebagai trade-off; dampaknya terbatas pada warmup awal; tidak ada glitch setelah warmup.

### Solusi

**Opsi (opsional):** Pre-allocate di `nativeCreate` berdasarkan `sampleRate` dan perkiraan max buffer size:

```cpp
// Di nativeCreate, setelah handle->channels = channels:
const int kMaxExpectedFrames = 8192;  // cukup untuk semua config ExoPlayer
handle->ensureCapacity(kMaxExpectedFrames, kMaxExpectedFrames);
```

Ini memastikan tidak ada alokasi di audio thread setelah create. Trade-off: alokasi lebih besar saat init (8192 * channels * 2 floats ≈ 256KB untuk stereo).

---

## Temuan #8

### Severity: **LOW** (Arsitektur / Dead Code)

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/jni_common.h`
- **Line:** 19–32

### Penjelasan

```cpp
// jni_common.h
enum class ErrorCode : int32_t {
    kOk = 0, kUnsupportedFormat = 1, kCorruptedFile = 2,
    kWriteFailure = 3, kPermissionFailure = 4, kFileNotFound = 5,
    kInvalidArgument = 6, kUnknown = 7, kVerificationFailed = 8,
};
```

```cpp
// tag_writer.h — IDENTIK byte-for-byte
enum class WriteResult : int32_t {
    kOk = 0, kUnsupportedFormat = 1, kCorruptedFile = 2,
    kWriteFailure = 3, kPermissionFailure = 4, kFileNotFound = 5,
    kInvalidArgument = 6, kUnknown = 7, kVerificationFailed = 8,
};
```

`ErrorCode` di `jni_common.h` adalah duplikat persis dari `WriteResult` di `tag_writer.h`, dengan nilai yang sama persis. `replaygain_jni.cpp` menggunakan `WriteResult` di semua tempat dan tidak pernah mereferensikan `ErrorCode`.

Konfirmasi: `grep -n "ErrorCode" *.cpp *.h` hanya menunjukkan deklarasi di `jni_common.h` — tidak ada penggunaan.

**Dampak:**
Dead code. Maintenance burden: jika nilai baru ditambahkan ke `WriteResult`, `ErrorCode` juga harus diupdate atau akan drift. Tidak ada dampak runtime.

### Solusi

Hapus `enum class ErrorCode` dari `jni_common.h`. `jni_common.h` hanya perlu berisi `JStringToStd` dan `StdToJString`.

---

## Temuan #9

### Severity: **LOW** (Arsitektur / Dead Field)

### Lokasi
- **File:** `android/app/src/main/cpp/replaygain/tag_writer.h`
- **Struct:** `WriteRequest`
- **Line:** 21 (`path` field)

### Penjelasan

```cpp
struct WriteRequest {
    std::string path;   // ← TIDAK PERNAH DIPAKAI di fd-based API
    TagFormat   format = TagFormat::kMp3;
    double track_gain_db = 0.0;
    // ...
};
```

`WriteRequest::path` adalah sisa dari path-based API yang sudah dihapus di sesi sebelumnya. Seluruh fd-based API (`WriteReplayGainTagsFd`, `RemoveReplayGainTagsFd`, dll.) tidak membaca field `path`. Di `replaygain_jni.cpp`, `BuildWriteRequest()` tidak men-set field `path`:

```cpp
WriteRequest BuildWriteRequest(TagFormat format, ...) {
    WriteRequest req;
    req.format = format;
    req.track_gain_db = track_gain_db;
    // ... tidak ada req.path = ...
    return req;
}
```

**Dampak:**
- Pemborosan memori kecil (satu `std::string` per `WriteRequest`)
- Kebingungan bagi maintainer yang membaca struct
- Tidak ada dampak runtime atau correctness

### Solusi

Hapus field `path` dari `WriteRequest`:

```cpp
struct WriteRequest {
    // path dihapus — API fd-based tidak memerlukan path;
    // format ditentukan oleh parameter 'format' di setiap fungsi.
    TagFormat   format = TagFormat::kMp3;
    double track_gain_db = 0.0;
    double track_peak_linear = 0.0;
    // ...
};
```

Semua pemanggil sudah tidak men-set `path`, jadi tidak ada perubahan di sisi pemanggil.

---

---

# AREA YANG DIAUDIT TANPA TEMUAN

Kategori berikut diaudit dan **tidak ditemukan bug**:

## Undefined Behavior
- **Signed integer overflow:** Tidak ditemukan. Semua operasi aritmetika yang relevan menggunakan int64_t atau size_t dengan batas yang aman. Konversi syncsafe MP3 menggunakan shift explicit pada `int64_t` — aman.
- **Strict aliasing:** Satu-satunya reinterpret_cast yang relevan adalah `reinterpret_cast<const int16_t*>(elems)` di JNI (jshort → int16_t, same-size, same-signedness — defined behavior) dan `reinterpret_cast<const jbyte*>(region.bytes.data())` (char → jbyte, keduanya 1-byte signed — defined behavior per C++ standard 6.10).
- **Dangling pointer / use-after-free:** Tidak ada. TagLib::File objek tidak di-store di luar function scope. EburAnalyzer lifetime dikelola via `unique_ptr` di registry dengan mutex. StretchHandle diakses hanya via Kotlin-provided handle.
- **Null dereference:** Semua pointer di-check sebelum dereference. TagLib::Tag* null check ada di semua format branches.

## Memory Safety
- **Buffer overflow/underflow:** `snprintf` digunakan dengan `sizeof(buf)` di semua tempat — tidak ada overflow. `PreadExact` loop menggunakan `ssize_t n <= 0` sebagai sentinel — benar.
- **Use-after-move:** Tidak ada. `std::move` digunakan sekali (`states.push_back(std::move(analyzer))`... wait, ini bukan move — `it->second->raw_state()` saja).
- **Stack corruption:** Buffer stack di stretch_jni.cpp (`char buf[96]`) diisi dengan `snprintf(buf, sizeof(buf), ...)` — aman.

## Thread Safety
- **Race condition pada g_registry:** `g_registry_mutex` menggunakan `std::mutex` + `std::lock_guard` di semua akses (RegisterAnalyzer, LookupAnalyzer, DestroyAnalyzer, komputasi album). `nativeComputeAlbumLoudness` menahan lock selama pointer collection DAN komputasi — benar, mencegah use-after-free jika track dihapus saat komputasi.
- **gProcClass / gLogMutex:** Inisialisasi lazy di bawah lock — thread-safe. Double-checked pattern tidak dipakai (single lock throughout).
- **StretchHandle dari audio thread:** Setiap ExoPlayer instance memiliki handle sendiri; tidak ada sharing. Dokumentasi jelas: "never shared or called concurrently."
- **Atomic misuse:** Tidak ada `std::atomic` yang dipakai salah. Tidak ada atomic dalam codebase ini.

## Audio DSP
- **NaN/Infinity propagation (stretch_jni.cpp):** Ditangani dengan benar: `std::isfinite(s) ? s : 0.0f` di output loop dan flush loop. Input NaN tidak mempengaruhi output karena sanitasi di output.
- **Denormal float:** Signalsmith Stretch adalah header-only library; penanganan denormal ada di library-nya. Tidak ada custom DSP di kode kita yang berpotensi menghasilkan denormal.
- **LUFS calculation (ebur128_analyzer.cpp):** `std::isfinite(integrated)` dicek sebelum `LufsToReplayGainDb`. `std::log10(tp)` hanya dipanggil jika `tp > 0.0`. True peak untuk nilai 0 diset ke `-HUGE_VAL` — benar. `std::lround` dipakai untuk konversi Q7.8 dengan clamping yang benar di domain double.
- **Sample rate bug:** Sample rate diteruskan ke libebur128 sebagai `uint32_t` (dicek `> 0` di `Create()`). Ke Signalsmith sebagai `float` via `presetDefault(channels, float(sampleRate))` — presisi float cukup untuk sample rate audio (44100, 48000, dll.).
- **Channel mismatch:** Tidak ada. libebur128 tahu channel count dari init. Signalsmith tahu dari `presetDefault`. Deinterleave/re-interleave menggunakan `h->channels` yang sama.

## JNI (selain LocalRef yang sudah dilaporkan)
- **GetPrimitiveArrayCritical misuse:** Tidak digunakan di codebase ini.
- **UTF string leak:** `JStringToStd` memanggil `ReleaseStringUTFChars` sebelum return — benar.
- **Exception handling:** `ExceptionClear()` dipanggil di tempat yang tepat di `bridgeToSystemLog` setelah `FindClass` dan `CallStaticVoidMethod` yang bisa melempar.
- **fd ownership:** Terdokumentasi jelas. JNI caller melepas fd via `detachFd()`, native mengambil ownership, TagLib menutup via `fclose()`.

## SIMD / NEON
Tidak ada SIMD/NEON code dalam codebase kita. libebur128 dan Signalsmith Stretch mungkin menggunakan SIMD secara internal, tetapi itu tanggung jawab library masing-masing.

## Numerical Stability
- **Division by zero:** Tidak ada pembagian dalam kode kita. libebur128 menangani ini secara internal.
- **sqrt negatif:** `std::sqrt(inSumSq / inCount)` — `inSumSq` diakumulasikan dari kuadrat nilai (selalu ≥ 0), `inCount > 0` dicek sebelumnya. Aman.
- **Catastrophic cancellation:** Tidak relevan untuk kode ini (tidak ada pengurangan dua nilai besar yang hampir sama).

## Security
- **Path traversal:** Tidak ada operasi file via path dalam codebase ini (path-based API sudah dihapus).
- **Unsafe memcpy/sprintf:** `snprintf` dipakai dengan `sizeof(buf)` — aman. `std::memcmp` dengan ukuran yang dikontrol — aman.
- **Integer overflow yang menyebabkan unsafe size calculation:** `static_cast<size_t>(*current_size)` di `RestoreMetadataRegionFd` bisa menjadi masalah jika `current_size` negatif, tapi `DetermineMetadataRegionSize` hanya mengembalikan nilai ≥ 0 atau `nullopt` — aman.

---

---

# RINGKASAN

| Severity | Jumlah |
|---|---|
| **Critical** | 0 |
| **High** | 1 |
| **Medium** | 1 |
| **Low** | 7 |
| **Total** | **9** |

---

## Production Readiness

> **Perlu Perbaikan Minor**

Satu bug HIGH yang harus diperbaiki sebelum production (OOM dari malformed metadata). Satu bug MEDIUM yang perlu mitigasi (silent restore failure). Tujuh bug LOW yang bisa diperbaiki kapan saja. Tidak ada Critical.

Kualitas kode secara keseluruhan sangat baik:
- Thread safety di analyzer registry benar dan terdokumentasi dengan baik
- Ownership model JNI (fd, analyzer handles) jelas dan konsisten
- Error handling fd leak sudah diperbaiki di sesi sebelumnya
- Deinterleave/re-interleave Signalsmith benar
- LUFS dan R128 conversion numerically stable
- Parser binary (ID3v2, FLAC, Ogg) defensif dengan guard loops dan nullopt-on-ambiguity

Setelah perbaikan temuan #1 (ReadRegion cap), kode ini layak production.

---

## Daftar Prioritas Perbaikan

| Prioritas | Temuan | Severity | Effort | Justifikasi |
|---|---|---|---|---|
| 1 | **#1** ReadRegion OOM cap | HIGH | Sangat rendah (1 baris + konstanta) | Process kill dari malformed file; fix trivial |
| 2 | **#2** RestoreMetadataRegionFd insert verification | MEDIUM | Rendah (10 baris) | Silent data corruption pada restore; partial mitigation tersedia |
| 3 | **#3** LocalRef leaks PackSnapshot/PackWriteEnvelope | LOW | Rendah (8 DeleteLocalRef calls) | JNI spec compliance; tidak crash tapi salah |
| 4 | **#8** ErrorCode dead code di jni_common.h | LOW | Sangat rendah (hapus 14 baris) | Maintenance debt; bisa drift dari WriteResult |
| 5 | **#9** WriteRequest::path dead field | LOW | Sangat rendah (hapus 1 baris) | Kebingungan maintainer; tidak ada runtime cost |
| 6 | **#4** FsyncGuard dup() failure logging | LOW | Rendah (tambah log) | Visibility saat fsync silently skipped |
| 7 | **#7** ensureCapacity pre-alloc di nativeCreate | LOW | Sedang (tambah init call) | Eliminasi heap alloc di audio thread warmup |
| 8 | **#6** steady_clock throttle via counter | LOW | Rendah (ganti clock dengan counter) | Eliminasi VDSO call di audio thread |
| 9 | **#5** nativeAddFramesShort bounds check | LOW | Rendah (tambah GetArrayLength check) | Defensive; tidak akan terjadi dengan Kotlin caller yang benar |
