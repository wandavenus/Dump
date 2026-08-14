# Deep Code Audit — 2026-08-14

Audit menyeluruh `lib/` (Dart) + `android/` (Kotlin + C++ JNI) + `native_audio_runtime/` (C DSP + JNI + FFI Dart).
Metode: `flutter analyze` (baseline), pembacaan penuh file inti, trace call-path lintas-batas
(Dart → MethodChannel/EventChannel/FFI → Kotlin → JNI → C/C++ → kembali), verifikasi status temuan
audit sebelumnya (12/13 Agustus), dan pencarian pola bug baru di area yang belum pernah diaudit
(C/C++ DSP, JNI boundary, identity/cache race). **Tidak ada kode yang diubah.**

---

## 1. Scope & baseline

| Direktori | Cakupan | Hasil |
|---|---|---|
| `lib/` | 260+ file Dart, ±38k baris | `flutter analyze lib` → **No issues found** |
| `android/` | 39 file Kotlin produksi + 8 C/C++ | Kotlin: temuan K1/K2 dari audit 13/08 **terverifikasi sudah di-fix**; C++ dibaca penuh |
| `native_audio_runtime/` | 19 file C + JNI + 8 file Dart | **Pertama kali diaudit**; kualitas tinggi, temuan minor |
| `native_audio_runtime/test|tool` | test/benchmark/ffigen | Dev-only; error `package:test`/`ffigen` karena dev-deps tidak ter-install di nested package — bukan bug produksi |

Catatan: lingkungan tidak punya Android SDK → verifikasi Kotlin/C++ adalah statis (tidak dikompilasi),
konsisten dengan audit sebelumnya.

---

## 2. Verdict 3 temuan ReplayGain (target audit sebelumnya)

### RG-1 🔴 "Cache invalidation setelah removeReplayGain" → **FALSE POSITIVE** (sebagai bug produksi) dengan residual **CONFIRMED WEAKNESS** (race `_inFlight`, self-healing)

**Pertanyaan wajib dibuktikan:**

1. **Apakah `_cache[song.id]` bisa berisi data lama setelah remove sukses?** Bisa *sesaat* lewat race
   `_inFlight` (lihat #8), tapi setiap jalur normal sudah menghapusnya: `removeReplayGainTags` →
   `await invalidate(song.id)` (`lib/services/replay_gain_service/service.dart:934`), dan
   `writeReplayGain` → `:904`. `invalidate()` (:112-125) menghapus `_cache`, `_cacheIdentity`, dan
   seluruh 6 key SharedPreferences `rg_<id>_{gain,peak,src,path,size,mtime}`.
2. **Apakah SharedPreferences masih bisa berisi data lama?** Tidak pada jalur normal — `invalidate()`
   menghapus semua key yang ditulis `_saveToPrefs`. Satu-satunya celah adalah resolve in-flight yang
   menulis ulang prefs **dengan identity lama** (lihat #8) — langsung invalid pada resolve berikutnya
   karena `_loadFromPrefs` membandingkan path+size+mtime (`service.dart:366-374`).
3. **Apakah caller remove memanggil invalidate setelah sukses?** **Ya, selalu** — `removeReplayGainTags`
   (:934) dan `writeReplayGain` (:904), dipanggil oleh UI maupun `removeReplayGainFromLibrary` (batch,
   per-song). Tidak ada jalur remove produksi yang melewatkan invalidate.
4. **Apakah invalidasi native `MetadataCacheDb` cukup?** Tidak perlu "cukup" karena Dart juga invalidate,
   tapi native memang meng-invalidate: `ReplayGainBridge.removeReplayGain`
   (`android/.../replaygain/ReplayGainBridge.kt:201-205`) memanggil `metadataCacheDb.invalidateByPath(path)`
   setelah `error == NONE`. Selain itu `MetadataCacheDb.get/getByPath` menolak row yang mtime-nya tidak
   cocok (`MetadataCacheDb.kt:141-145, 220-223`) — mtime selalu berubah setelah TagLib menulis ulang file,
   jadi cache SQLite **ganda**-invalid (eksplisit + implicit).
5. **Apakah mtime/size berubah setelah remove sehingga cache otomatis invalid?** mtime **selalu** berubah
   (file ditulis ulang oleh TagLib). size bisa kebetulan sama, tapi mtime yang berubah sudah cukup
   memecah identity. Race hanya jika mtime cocok *tepat-ms* — lihat RG-2.
6. **Kalau mtime/size tidak berubah, apakah stale value reachable?** Hanya pada filesystem dengan
   granularitas mtime kasar (FAT32/exFAT SD, 2 detik) + ukuran identik — lihat RG-2. Di ext4/F2FS internal
   (ms) praktis tidak.
7. **Apakah `_cacheIdentity` mencegah stale value?** Ya — setiap baca memory cache membandingkan
   `_cacheIdentity[song.id] == identity` (`service.dart:42-46`), dan stale identity di-evict lalu
   di-re-read. Ini juga satu-satunya alasan race #8 tidak pernah menghasilkan stale *persisten*.
8. **Apakah `_inFlight` bisa memberi stale result setelah remove?** **Ya, ada window nyata:**
   - `resolve()` #1 mulai: `_fileIdentity` → identity A → `_inFlight[id] = future` → native read berjalan.
   - `removeReplayGainTags` sukses → `invalidate()` membersihkan cache+prefs tapi **tidak** `_inFlight`.
   - `resolve()` #2 datang setelah invalidate → identity B (baru) → cache kosong → `_inFlight[id]` masih
     ada → **#2 menerima hasil future #1 (data lama)**. Future #1 juga menulis ulang `_cache`/prefs
     dengan identity A.
   - Self-heal: resolve #3 membandingkan identity B vs A → miss → re-read → benar.
   - **Reachable dari produksi?** Tidak terbukti untuk perilaku salah yang persisten; window hanya
     beberapa ms dan remove adalah aksi user (jarak detik dari resolve). Dampak maksimal: gain salah
     sekali hingga resolve berikutnya.
9. **Race `resolve() ‖ removeReplayGain()`?** Secara konkret mustahil di lintas-thread (semua via
   MethodChannel, di-main-thread kotlin + satu UI isolate), dan self-healing identity menutup dampak
   jangka panjangnya.

**Verdict:** `remove → invalidate → resolve` pada jalur produksi **benar** di ketiga lapisan (Dart
memory, Dart prefs, SQLite native). Klaim "resolve masih dapat ReplayGain lama" **tidak terbukti**
sebagai bug produksi → **FALSE POSITIVE** untuk severity yang diklaim. Residual: `_inFlight` tidak
dibersihkan oleh `invalidate()` → **CONFIRMED WEAKNESS** (low, self-healing).

**Rekomendasi:** `invalidate()` juga hapus `_inFlight.remove(songId)`; dan dedup `_inFlight` sebaiknya
keyed `(songId, identity)` bukan `songId` saja.

### RG-2 🟠 "mtime + size sebagai file identity" → **CONFIRMED WEAKNESS** (granularity mtime), bukan bug pada storage internal modern

**Bukti:** `_ReplayGainFileIdentity` = `(path, size, mtimeMs)` dengan `==` atas ketiganya
(`lib/services/replay_gain_service.dart:27-47`). Sumber: `getReplayGainFileIdentity` →
`File.length()` + `File.lastModified()` (`MainActivity.kt:531-546`). SQLite native memakai mtime saja
(`MetadataCacheDb.get(songId, mtime)`).

1. **Cache valid hanya atas path+size+mtime?** Ya — tidak ada identity lain (tidak ada checksum/inode).
2. **Apakah song.id ikut menjamin identity?** Tidak. MediaStore `_ID` adalah id row, dan file yang
   diganti di tempat (update row) mempertahankan `_ID` yang sama. Justru karena itu identity
   path+size+mtime ada. Jadi song.id **bukan** identity file — dan ini sudah di-design dengan benar.
3. **Apakah `_ID` berubah saat file diganti?** Tidak selalu (update in-place). Konsisten dengan #2.
4. **Apakah write RG selalu mengubah size/mtime?** mtime **selalu** (TagLib menulis ulang). size tidak
   selalu. Untuk invalidation, mtime cukup.
5. **Kelemahan nyata:** perbandingan mtime **exact-ms**. Pada storage eksternal FAT32/exFAT
   (granularitas 2 detik), dua modifikasi dalam jendela 2 detik dengan ukuran identik menghasilkan
   identity sama → cache lama tetap terpakai untuk file baru. Pada ext4/F2FS internal Android, `stat`
   ms → praktis tidak terjadi. Juga: `File.lastModified()` pada file via MediaStore bisa mencerminkan
   row DB, bukan inode — perilaku bervariasi per OEM (runtime-dependent).

**Verdict:** CONFIRMED WEAKNESS (device/filesystem-dependent; tidak terbukti salah pada storage
internal modern). **Rekomendasi:** tambah komponen kedua yang kuat untuk file yang ditulis sendiri
(ukuran ± mtime sudah cukup di ext4; untuk SD card pertimbangkan menyimpan `cached_at` dan
memvalidasi ulang setelah TTL, atau cek inode/ctime via `FileKey` bila tersedia).

### RG-3 🟠 "fsync() failure handling" → **CONFIRMED WEAKNESS** (durability only; bukan bug in-session)

**Bukti:** `FsyncGuard::Sync()` (`android/app/src/main/cpp/replaygain/tag_writer.cpp:203-216`) memanggil
`::fsync(dup_fd_)` dan **mengabaikan return value** — didokumentasikan "best-effort: a failure here
doesn't change the overall WriteResult". Berlaku untuk semua jalur write/remove/restore (dipanggil
setelah setiap `file.save()`). `dup()` gagal hanya di-log.

**Analisis path produksi:**
- Write → `file.save()` (page cache) → `fsync()` (ignored) → Kotlin buka fd baru → verify. Verify
  membaca **page cache**, sehingga fsync gagal tidak terdeteksi oleh verifikasi.
- Dampak nyata hanya pada durability: jika fsync benar-benar gagal (EIO, storage penuh) lalu device
  mati, file bisa tertinggal setengah-tertulis (MP3: audio region ter-shift). Region backup + rollback
  hanya untuk kegagalan terdeteksi in-session, bukan power loss.
- **Counter-evidence:** dalam sesi normal tidak ada perilaku salah yang bisa dibuktikan; fsync gagal
  tanpa power-loss tidak terlihat oleh pengguna. Verifikasi + rollback byte-exact menutup kegagalan
  terdeteksi.

**Verdict:** CONFIRMED WEAKNESS (durability/crash-window; runtime-dependent). **Rekomendasi:** jadikan
`Sync()` mengembalikan bool dan bila gagal, propagasikan error ke Kotlin sebagai
`WRITE_NOT_DURABLE` (jangan klaim "persisted"), atau minimal log warning.

---

## 3. Status temuan audit sebelumnya (verifikasi)

| Temuan | Status sekarang |
|---|---|
| K1 (P2) crossfade cancel → queue tidak di-rebuild | **FIXED** — `CrossfadeController.cancel()` (:161-201) menangkap `wasMidFade` lalu `rebuildPromotedQueue()` → `queueManager.rebuildPlayerQueue()` (di-wire di `Media3PlaybackService.kt:428`). noisyReceiver (:196-207) dan onFocusLoss (:331-340) dijamin lewat jalur yang sama. |
| K2 (P2) akumulasi AudioOffloadListener | **FIXED** — `attachOffloadListenerTo()` (:793-801) remove dari semua player lalu add satu listener tracked. Untracked add di `createConfiguredPlayer()` sudah dihapus. |
| D1 (history int.parse) | **FIXED** — `int.tryParse` + `whereType<int>` (`history_service.dart:53-54, 99-100`). |
| D2 (playlist id tabrakan) | **FIXED** — `Random.secure()` ditambahkan ke id (`playlist_service.dart:42,51`). |
| D3 (scroll_to_top RangeError) | **FIXED** — `_clampIndex` (`scroll_to_top_service.dart:14-19`). |
| D4 (focus transient dead param) | **FIXED** — parameter dihapus; `AudioFocusService` sekarang thin wrapper. |
| D5 (palette self-reschedule timer) | **FIXED** — guard `_dirty=false` di `_persist`. |
| D6 (lyrics 15s timer leak) | **FIXED** — `Future.delayed` diganti `Timer` eksplisit + `cancel()` di `finally` (`fetch_manager.dart:261-275`). |
| F3/F5/F6, LOW-06, MED-02, A2, R-B 1.5.21/1.5.23 | Terverifikasi masih ada di tempat (identity before/after scan, queue-mutation guard + re-sync, drop unparseable prefs, timeout startup 5s/2s, empty-queue propagation, artwork eviction on delete, batched write path + chunk 250 + dedup). |
| Artwork (11/08): stale async notification, crossfade session refresh, process-wide lock, external-file artwork | Belum diaudit ulang mendalam di putaran ini (sudah diaudit 11/08); rekomendasi di laporan tersebut masih berlaku. |

---

## 4. Temuan baru

### N1 (P3) — `ReplayGainService.clearCache()` tidak dipanggil di mana pun (dead code)

- **File:** `lib/services/replay_gain_service/service.dart` (definisi), tidak ada caller di `lib/`.
- **Execution path:** tidak ada. Setelah library re-scan, cache Dart/prefs lama untuk song yang
  dihapus/diganti tidak pernah dibersihkan massal — tapi identitas (path+size+mtime) dan `_ID` unik
  membuat dampaknya nol: song baru di path baru tidak akan pernah match `_cache[songId lama]`.
- **Verdict:** CONFIRMED WEAKNESS (cosmetic; dead API). Severity: note.

### N2 (P3) — `scanLibrary` selalu me-rescan lagu tanpa data RG (gainDb == 0.0)

- **File:** `lib/services/replay_gain_service/service.dart:497-503`.
- **Bukti:** skip-condition memakai `c.gainDb == 0.0`; `LoudnessData.none()` punya `gainDb = 0.0`
  (`lib/models/loudness_data.dart:34-37`). Artinya lagu yang **tidak punya tag RG** (mayoritas
  library) di-decode penuh ulang oleh native setiap batch scan, meski identity-nya valid dan sudah
  pernah di-scan.
- **Counter-evidence:** tidak salah secara fungsional (hanya boros); native SQLite cache tidak dipakai
  sebagai sumber skip di sini.
- **Verdict:** CONFIRMED WEAKNESS (performance; library besar → puluhan menit scan berulang).
- **Rekomendasi:** skip jika `_cacheIdentity[song.id] == identity` terlepas dari nilai gain, atau
  konsultasikan SQLite `getByPath` sebelum memutuskan.

### N3 (P3) — `_prefetchPalette` menjatuhkan song saat cap concurrency tercapai (tidak pernah di-retry)

- **File:** `lib/services/audio/playback_manager.dart` (`_prefetchPalette`).
- **Bukti:** `if (_activePrefetches >= _maxConcurrentPrefetches) { _prefetchingSongs.remove(songId); return; }`
  — song dihapus dari set dedup tapi tidak diantre; event currentTrack berikutnya untuk song sama
  sudah di-`return` oleh guard `_lastPrefetchedIndex/NextIndex`, jadi palet tidak pernah di-prefetch.
- **Dampak:** background player / queue overlay bisa menampilkan placeholder saat skip cepat 3+ lagu
  beruntun. Kosmetik (player fallback tetap jalan).
- **Verdict:** CONFIRMED WEAKNESS (cosmetic; low).

### N4 (P3) — `nativeProcess` (stretch) tanpa capacity check pada direct buffer

- **File:** `android/app/src/main/cpp/stretch/stretch_jni.cpp` (`nativeProcess`/`nativePrime`/`nativeFlush`).
- **Bukti:** `GetDirectBufferAddress` dipakai tanpa `GetDirectBufferCapacity` — kontras dengan
  `native_dsp_jni.c` yang memvalidasi kapasitas. OOB hanya mungkin jika Kotlin mengirim
  `inputFrames/outputFrames` melebihi buffer yang dialokasikan.
- **Reachable?** Tidak ditemukan caller Kotlin yang bisa memproduksi itu (`SignalsmithStretchAudioProcessor`
  mengalokasikan buffer dari ukuran yang sama dengan yang ia beritahu native).
- **Verdict:** CONFIRMED WEAKNESS (defensive gap; tidak reachable saat ini). Severity: low.

### N5 (P3) — `_ReplayGainApplicator` (jalur playback) melewati cache SharedPreferences Dart

- **File:** `lib/services/loudness_source_resolver.dart:30` → `ReplayGainService.resolveBoth` →
  `_readRawTags` (channel `getReplayGainTags`) langsung.
- **Bukti:** satu-satunya caller `resolve()` (yang memakai `_cache` + prefs Dart) adalah
  `song_metadata_service/service.dart:84` (song-info sheet). Jalur playback memakai SQLite native
  (mtime-validated) — benar dan aman, tapi berarti dua cache terpisah, dan key `rg_*` di prefs tidak
  pernah mempercepat playback.
- **Verdict:** CONFIRMED WEAKNESS (duplikasi cache; bukan bug). Severity: note.

### N6 (P3) — `_ln_process` (loudness) memakai ring 4×100ms dengan window 400ms tetapi gain target
tidak di-update saat seluruh blok di-gate (rel_count == 0)

- **File:** `native_audio_runtime/src/loudness_processor.c` (`_ln_process`, gating block).
- **Bukti:** jika `abs_count == 0` atau `rel_count == 0` (track hampir sunyi), `gain_target` tidak
  diubah — perilaku yang didokumentasikan (absolute-gate contract). Benar untuk gating, tapi artinya
  track sunyi mempertahankan gain dari track sebelumnya sampai blok berikutnya lolos gate.
- **Dampak:** pada transisi track, `nar_loudness_reset()` dipanggil Dart (stream-0), jadi baseline
  di-reset; sisa window hanya pada jalur crossfade stream-1 yang tidak di-reset (known limitation
  yang sudah didokumentasikan di file header).
- **Verdict:** CONFIRMED WEAKNESS (known limitation; sudah didokumentasikan; inaudible ≤ 400 ms).

---

## 5. Verified strengths (native_audio_runtime + C++ — area baru)

- **DSP pipeline** (`dsp_pipeline.c`): lock-free hot path, atomics per-slot, `_initialized` guard di
  `process_stream` + `process_raw_stream` (fail-open, crash-safe terhadap dispose race), chain tidak
  berhenti saat satu processor error (limiter/clipper safety net selalu jalan), NAR-2/NAR-4 fix
  terdokumentasi.
- **ReplayGain processor** (`replaygain_processor.c`): per-stream gain (`NAR_DSP_MAX_STREAMS`), bit-
  pattern atomics (bebas lock pada ABI target), clipping protection + clamp ±24 dB, NEON scalar path
  dengan NaN sanitize.
- **Loudness processor** (`loudness_processor.c`): koefisien BS.1770-4 literal + prewarp tan(), per-
  stream SR auto-detect, fail-open NaN/Inf, race NAR-3 dianalisis dan diterima dengan rasional,
  NAR-5 per-stream reset API.
- **JNI replaygain** (`replaygain_jni.cpp`): bounds-check `frame_count × channels ≤ array_len`
  (Temuan #5 di-fix), registry handle dengan mutex (anti use-after-free album scan), semua local ref
  di-delete (fix Temuan #3/#8), rollback verify penuh.
- **Tag writer** (`tag_writer.cpp` + `metadata_region.cpp`): region backup byte-exact sebelum mutasi,
  cap 64 MB (fix Temuan #1), abort alih-alih menebak untuk ID3 syncsafe rusak / FLAC / Ogg header
  parsing, verify-sentinel (title/artist/album) + verify isi, restore + re-verify, RemoveTxxx untuk
  SEMUA frame duplikat.
- **Stretch** (`stretch_jni.cpp`): fail-closed (negatif status = output kosong), scratch grow-only
  (tanpa alokasi heap di audio thread), prewarm 8192 frame, frame-counter throttle (tanpa syscall
  clock), NaN sanitize, single-handle-per-player (tidak di-share).
- **FFI Dart** (`runtime_impl_io.dart`, `dsp_pipeline_io.dart`): lifecycle eksplisit,
  `duplicateModule` ditoleransi (hot restart), `_dspGuard` fail-open di PlaybackManager (semua
  binding native lewat satu choke point), dispose idempotent.
- **MainActivity dispatch:** semua handler via `submitBackground` (bounded executor + `onRejected`
  backpressure) + `postToFlutter`; write/remove ReplayGain lewat `MediaStoreWriteGate` yang
  menserialisasi dialog grant (bug dialog orphan lama sudah di-fix dengan queue).
- **Native K2 fix untuk mtime ordering:** mtime disampling SEBELUM read (bukan sesudah) di
  `getSongExtendedTags`/`getReplayGainTags` → stale bytes tidak pernah terikat ke mtime baru
  (self-healing).

---

## 6. Test gap

- Tidak ada unit test untuk race `_inFlight` vs `invalidate` (RG-1 #8). Regression test bernilai:
  resolve in-flight → remove → resolve baru → pastikan tidak menerima future lama.
- Tidak ada test untuk granularity mtime (exFAT) — sulit tanpa device; bisa disimulasikan dengan
  identity injection.
- `native_audio_runtime/test/native_audio_runtime_test.dart` ada tapi dev-deps (`package:test`)
  tidak ter-install di nested package → tidak bisa dijalankan dari root. Jika ingin menjalankan,
  perlu `cd native_audio_runtime && flutter pub get` dulu.
- Kotlin unit test (`android/app/src/test`) tidak bisa dijalankan tanpa Android SDK di environment ini.

---

## 7. Kesimpulan

Kualitas keseluruhan **tinggi dan konsisten**: praktik defensif (fail-open di semua batas native,
bounded executors, verifikasi + rollback byte-exact, identity-guard pada tiap cache) dan semua temuan
P2/P3 dari audit sebelumnya sudah diterapkan dan terverifikasi. Tidak ditemukan **Confirmed bug P1/P2
baru** di jalur produksi pada ketiga direktori.

Tiga temuan ReplayGain lama: **RG-1 = FALSE POSITIVE** (sebagai bug; residual race `_inFlight` =
weakness low), **RG-2 = CONFIRMED WEAKNESS** (granularity mtime pada storage eksternal),
**RG-3 = CONFIRMED WEAKNESS** (durability fsync). Temuan baru semuanya P3/note, tidak ada yang
mengubah perilaku produksi hari ini.

Prioritas perbaikan yang disarankan (jika mau lanjut): (1) `invalidate()` bersihkan `_inFlight`,
(2) `scanLibrary` skip berdasarkan identity bukan `gainDb == 0.0`, (3) `FsyncGuard::Sync()` laporkan
kegagalan, (4) capacity check di stretch JNI.

---

## 8. Follow-up — 4 perbaikan prioritas diterapkan (lanjutan)

Setelah audit, empat perbaikan prioritas dieksekusi. Verdict audit tidak berubah — ini menutup
residual yang sudah teridentifikasi, bukan menemukan bug baru.

| # | Fix | File | Ringkasan |
|---|---|---|---|
| 1 | RG-1 residual (`_inFlight`) | `lib/services/replay_gain_service/service.dart` (`invalidate`) | `invalidate()` kini juga `_inFlight.remove(songId)`. Caller resolve yang datang setelah remove tidak lagi bergabung ke future lama dan menerima/menulis-ulang data pra-remove. Nilai stale yang masih sempat ditulis future yang sudah berjalan tetap terikat identity lama dan ditolak semua resolve berikutnya. |
| 2 | N2 (`scanLibrary` re-scan) | `lib/services/replay_gain_service/service.dart` (`scanLibrary`) | Skip-condition memakai `!c.hasData` (source != none) menggantikan `c.gainDb == 0.0`. Lagu dengan nilai loudness nyata (tag "+0.00 dB" atau hasil ukur tepat −18 LUFS) tidak lagi di-decode ulang tiap batch scan; `LoudnessData.none()` tetap di-scan seperti sebelumnya. |
| 3 | RG-3 (fsync) | `android/app/src/main/cpp/replaygain/tag_writer.cpp` (`FsyncGuard::Sync`) | Return `::fsync()` tidak lagi dibuang: kegagalan di-log dengan errno (stderr → logcat). Semantik tetap best-effort (tidak mengubah WriteResult) — durabilitas kini terlihat di log. |
| 4 | N4 (stretch JNI) | `android/app/src/main/cpp/stretch/stretch_jni.cpp` (`nativeProcess`/`nativePrime`/`nativeFlush`) | Capacity check `GetDirectBufferCapacity` ≥ frames × channels × 4 B sebelum akses memory; kegagalan → fail-open -1 (bukan OOB). Tidak memicu pada path nyata (Kotlin selalu mengalokasikan ukuran eksak). |

**Verifikasi:** `flutter analyze lib` → No issues found. `stretch_jni.cpp` lolos `g++ -fsyntax-only`
(dengan stub jni.h). `tag_writer.cpp` tidak bisa dikompilasi di environment ini (TagLib via
FetchContent saat Gradle build) — perubahan minimal dan mengikuti pola log `fprintf(stderr)` yang sudah ada.

RG-2 (granularity mtime pada storage eksternal FAT32/exFAT) **tidak diubah**: tergantung device,
tidak terbukti salah pada storage internal modern (Mi 9T/ext4), dan fix yang tepat memerlukan
keputusan desain (mis. simpan `cached_at` + TTL revalidasi atau cek inode/ctime).

---

## 9. Verifikasi lanjutan (turn berikutnya) — evidence registry eksak + status working tree

Re-verifikasi semua klaim di atas terhadap source code aktual (bukan hanya dokumen).

**Status working tree saat ini (belum di-commit):**

- `M lib/services/replay_gain_service/service.dart` — fix RG-1 (`_inFlight` di `invalidate`) + fix N2 (`scanLibrary` skip `!c.hasData`)
- `M android/app/src/main/cpp/replaygain/tag_writer.cpp` — fix RG-3 (`fsync` return di-log)
- `M android/app/src/main/cpp/stretch/stretch_jni.cpp` — fix N4 (capacity check direct buffer)
- `?? Deep_Code_Audit_2026-08-14.md` — dokumen ini

**Registry evidence per finding (file:line — semua diverifikasi ulang 14/08):**

### RG-1 — Cache invalidation setelah remove

| Lapisan | Bukti |
|---|---|
| Dart `resolve()` | `service.dart:37`; guard memory cache vs identity di `:42-46`; dedup `_inFlight` di `:57-62` |
| Dart `invalidate()` | `service.dart:112-125` — hapus `_cache`, `_cacheIdentity`, `_inFlight.remove(songId)` (`:121`), + 6 key prefs `rg_<id>_{gain,peak,src,path,size,mtime}` |
| Dart `removeReplayGainTags` | `service.dart:934-952` — `await invalidate(song.id)` hanya saat `success == true` |
| Dart `writeReplayGain` | `service.dart:859+` — `await invalidate(song.id)` setelah sukses |
| Caller batch | `removeReplayGainFromLibrary` (service.dart) — dedup songId + per-song `removeReplayGainTags` |
| Caller UI | `batch_scan_section.dart:136` (Settings → hapus RG); `song_context_menu.dart:283-284` (edit/delete → `ReplayGainService.invalidate`) |
| Kotlin remove | `ReplayGainBridge.kt:244-262`; `metadataCacheDb.invalidateByPath(path)` di `:260` setelah `NONE` |
| Kotlin write | `ReplayGainBridge.kt:158-218`; `invalidateByPath(path)` di `:216` |
| SQLite mtime guard | `MetadataCacheDb.kt:169` (`get`), `:208` (`getByPath`) — row ditolak jika `storedMtime != mtime` |
| Prefs validation | `_loadFromPrefs` (`service.dart:366-374`) — path+size+mtime harus cocok sebelum prefs dipakai |

**Pertanyaan wajib #8 (race `_inFlight`)**: window lama (resolve #1 → remove → resolve #2 menerima future #1)
sudah **ditutup** oleh `_inFlight.remove(songId)` di `invalidate()` (`:121`). Future #1 yang sudah berjalan
masih bisa menulis data pra-remove ke `_cache`/prefs, tapi nilainya terikat identity lama dan ditolak oleh
semua resolve berikutnya (self-healing, `:42-46`). Verdict bertahan: **FALSE POSITIVE** sebagai bug produksi;
residual weakness yang tersisa sudah di-fix.

### RG-2 — mtime + size identity

- `_ReplayGainFileIdentity` = `(path, size, mtimeMs)` dengan `==` atas ketiganya — `replay_gain_service.dart:29-47`.
- Sumber identity: `getReplayGainFileIdentity` (MainActivity.kt) → `File.length()` + `File.lastModified()`; tidak ada checksum/inode.
- SQLite native memakai **mtime saja** (`MetadataCacheDb.get(songId, mtime)`).
- Guard F3 di native: mtime disampling SEBELUM read di `scanTrack` (`ReplayGainBridge.kt:40-75`) dan `scanAlbum` — byte basi tidak pernah terikat ke mtime baru.
- Verdict bertahan: **CONFIRMED WEAKNESS** (exact-ms; hanya rentan di filesystem granularitas kasar FAT32/exFAT + ukuran identik; tidak terbukti salah di ext4/F2FS internal Mi 9T). Tidak diubah — butuh keputusan desain (cached_at + TTL / cek inode-ctime).

### RG-3 — fsync() failure handling

- `FsyncGuard` — `tag_writer.cpp:247`; `Sync()` — `:268-276`: `::fsync(dup_fd_) != 0` kini di-log dengan errno (`:270-275`), semantik tetap best-effort (tidak mengubah WriteResult).
- Fix RG-3 sudah terpasang di working tree (`git diff` menampilkan `#include <cerrno>` + branch `if (::fsync(...) != 0) { fprintf(stderr, ...) }`).
- Verdict bertahan: **CONFIRMED WEAKNESS** (durability/crash-window hanya; tidak ada perilaku salah in-session yang bisa dibuktikan — verify membaca page cache).

**Verifikasi:** `flutter analyze lib` → **No issues found** (Flutter 3.47.0, 2.5s). Kotlin/C++ tetap tidak bisa dikompilasi di environment ini (tanpa Android SDK/TagLib) — perubahan minimal dan mengikuti pola yang sudah ada.
