# Full Code Audit — 2026-08-12

Audit menyeluruh dan bertahap: `lib/` (Dart) → `android/` (Kotlin).

**Scope:** 277 file Dart (±38k baris) di `lib/`, lalu seluruh file Kotlin di `android/`.
**Metode:** analyzer statis (strict lints), trace call-path nyata, scan pola bug umum
(dispose/leak, listener, Timer, `.first` pada list kosong, channel boundary tanpa guard),
dan pembacaan mendalam file logika inti. Tidak ada kode yang diubah oleh audit ini.

---

# Bagian 1 — Audit `lib/` (Dart)

## Baseline statis

- `flutter analyze lib` → **No issues found** (1.7s).
- Lint ketat aktif: `use_build_context_synchronously`, `unawaited_futures`,
  `discarded_futures`, `close_sinks`, `avoid_dynamic_calls`, `strict-casts`,
  `strict-inference`, `strict-raw-types` (lihat `analysis_options.yaml`).
- Konsekuensi: kelas bug yang terdeteksi linter (context setelah await, future
  terbuang tanpa handler, sink tidak ditutup) sudah tidak ada. Fokus audit ini
  adalah **bug logika** yang tidak tertangkap analyzer.

## Ringkasan eksekutif

Kualitas `lib/` tinggi. Sub-sistem audio (PlaybackManager/AudioService/Media3Bridge),
ReplayGain, MediaStore, artwork, dan lyrics semuanya sudah melewati beberapa siklus
audit+fix (komentar ARCH-01/02, LOW-06, MED-02, F3/F5/F6, A2, R-B 1.5.21/1.5.23,
fail-open guard, timeout startup). Tidak ditemukan bug konfirmasi P1 pada jalur
produksi. Temuan yang ada semuanya P3 (weakness/notes), sebagian besar
practical-unreachable.

## Temuan

### D1 (P3) — `HistoryService.trackPlay` menangani entri korup secara inkonsisten

- **File:** `lib/services/history_service.dart:92` (juga `:51` di `warmUp`).
- **Bukti:**
  - `:92` — `_cachedRecentIds = recent.map(int.parse).toList(...)` → throw
    `FormatException` jika prefs berisi entri non-integer.
  - `:101` — `getRecentlyPlayedIds()` memakai `int.tryParse` + `whereType<int>`
    (komentar "F6 fix: drop unparseable entries instead of throwing").
  - `warmUp` (`:41-49`) membungkus dengan try/catch, sehingga jalur startup aman.
- **Execution path:** `AudioService._syncCurrentTrackFromNative` /
  `playSongAt` / `playFromCurrentQueue` → `unawaited(HistoryService.trackPlay(song))`
  → `recent.map(int.parse)` throw → error jatuh ke zone handler (ter-log, bukan crash).
- **Counter-evidence:** entri ditulis sendiri oleh `trackPlay` (`song.id.toString()`)
  — selalu integer. Hanya data legacy/korup yang bisa memicu; dan karena dipanggil
  via `unawaited`, tidak pernah crash aplikasi.
- **Verdict:** CONFIRMED WEAKNESS (inconsistent robustness; impact = log noise +
  write-through cache tidak ter-update pada sesi itu).
- **Rekomendasi:** samakan dengan pola F6 (`int.tryParse` + `whereType<int>`).

### D2 (P3) — `PlaylistService.createPlaylist` id rawan tabrakan

- **File:** `lib/services/playlist_service.dart:44`.
- **Bukti:** `id: DateTime.now().millisecondsSinceEpoch.toString()` — dua playlist
  dibuat dalam milidetik yang sama akan berbagi id → operasi rename/delete/addSong
  bisa mengenai playlist yang salah.
- **Reachable:** secara praktis tidak — alur UI (dialog berurutan) tidak bisa
  membuat dua playlist dalam <1ms. Catat sebagai note.
- **Verdict:** CONFIRMED WEAKNESS (theoretical; severity rendah).
- **Rekomendasi:** id acak (`Random.secure`) atau counter.

### D3 (P3) — `ScrollToTopService` tanpa bounds-check indeks

- **File:** `lib/services/scroll_to_top_service.dart:11,14`.
- **Bukti:** `signal(tabIndex)` dan `trigger(tabIndex)` meng-index `_signals[5]`
  tanpa validasi → `RangeError` untuk indeks di luar 0-4.
- **Reachable:** hari ini hanya dipanggil dari bottom nav (0-4). Tetap rapuh
  terhadap perubahan masa depan.
- **Verdict:** CONFIRMED WEAKNESS.
- **Rekomendasi:** clamp atau assert.

### D4 (P3) — `AudioFocusService.onFocusLoss` mengabaikan `transient`

- **File:** `lib/services/audio_focus_service.dart:20-21`.
- **Bukti:** parameter `transient` tidak dipakai; selalu memanggil
  `AudioSessionHandler.onAppPause()`.
- **Counter-evidence:** `AudioSessionHandler.onAppPause()` sekarang no-op —
  focus/NOISY ditangani native oleh Media3 (`handler.dart`). Jadi dampak aktual = nol.
- **Verdict:** CONFIRMED WEAKNESS (cosmetic; dead parameter).
- **Rekomendasi:** hapus parameter atau beri dokumentasi.

### D5 (P3) — `NativePaletteService._persist` dapat self-reschedule tanpa batas

- **File:** `lib/services/native_palette_service.dart` (fungsi `_persist`).
- **Bukti:** jika `_cacheFilePath == null`, `_persist` membuat `Timer(800ms, _persist)`
  ulang tanpa batas selama `_dirty == true`.
- **Reachable:** praktis tidak. Di Android `warmUp()` (dipanggil sebelum `runApp`)
  selalu meng-set `_cacheFilePath`; di web `_extract` tidak pernah memanggil
  `_schedulePersist()` (fallback tidak di-cache). Hanya reachable jika `get()`
  dipanggil sebelum `warmUp()` selesai — tidak terjadi di `main()`.
- **Verdict:** CONFIRMED WEAKNESS (theoretical; timer leak 800ms).
- **Rekomendasi:** guard satu kali (`if (path == null) { _dirty = false; return; }`).

### D6 (P3) — `LyricsFetchManager._runParallel` meninggalkan timer global 15s

- **File:** `lib/services/lyrics_service/fetch_manager.dart` (`_runParallel`).
- **Bukti:** `Future.any([allDone, upgrade, Future.delayed(15s)])` — ketika
  `allDone`/`upgrade` menang lebih dulu, `Future.delayed` 15s tetap hidup sampai
  timer-nya fired (satu timer mati per fetch; tidak menumpuk bahaya).
- **Impact:** minimal; timer sekali jalan, tidak memegang resource.
- **Verdict:** CONFIRMED WEAKNESS (hygiene).
- **Rekomendasi:** cancel timer eksplisit dengan `Timer` alih-alih `Future.delayed`.

### D7 (P3) — `fetch_manager.dart` mendefinisikan `unawaited` lokal

- **File:** `lib/services/lyrics_service/fetch_manager.dart` (bottom of file).
- **Bukti:** `void unawaited(Future<void> future) {}` — menaungi `dart:async`'s
  `unawaited` dan **menelan error** `_saveToDisk` yang tidak di-await.
- **Counter-evidence:** `putDisk` membungkus semua I/O dengan try/catch, jadi
  error tidak mungkin lolos. `_reconstructLrc` murni.
- **Verdict:** CONFIRMED WEAKNESS (pola; berisiko jika `_saveToDisk` berubah).
- **Rekomendasi:** pakai `unawaited` dari `dart:async` dengan error handler.

### D8 (Info) — Catatan performa

- `ArtworkRepository._resolvePath` memakai `file.statSync()` di UI thread
  (`artwork_repository.dart`) — sekali per cache miss; acceptable.
- `SongMetadataService._mtimeMs` memakai `File.lastModifiedSync()` —
  sekali per buka sheet info; acceptable.
- `WebView` widget membungkus hampir semua halaman dengan gradient + Scaffold
  (`webView/web_view_container.dart`) — pilihan arsitektur, bukan bug.

## Verifikasi temuan lama yang sudah di-fix (regresi check)

1. **ReplayGain cache invalidation setelah remove** — `removeReplayGainTags`
   → `invalidate(song.id)` membersihkan memory cache + 6 key SharedPreferences
   (`replay_gain_service/service.dart`). ✅ Fixed.
2. **mtime+size identity** — `_ReplayGainFileIdentity(path, size, mtimeMs)`
   dipakai konsisten: `resolve`, `_loadFromPrefs`, `scanOneSong`,
   `_scanTrackResult` (before/after guard), `scanAlbum` (before/after), dan
   `writeReplayGain` (stale-scan rejection). ✅ Fixed.
3. **fsync failure handling** — live di sisi Kotlin (`MediaStoreWriteGate`,
   verifikasi byte-exact + rollback); akan diverifikasi di Bagian 2.
4. **MediaStore cold-start** — stale-while-revalidate + timeout 20s + in-flight
   dedup + reconcile backoff 10s. ✅
5. **ArtworkRepository evict vs getPath race** — generation counter +
   `_pendingDeletes` await. ✅
6. **PlaybackManager fail-open DSP** — `_dspGuard` menyentuh `bindings.nar_*`
   hanya jika pipeline initialized. ✅
7. **Bit-Perfect mode** — snapshot/restore mencakup semua nilai yang di-mutasi
   oleh `_forceBypassEverything`. ✅

## Verified strengths (Dart)

- Satu-satunya MethodChannel/EventChannel edge: `Media3PlaybackBridge`
  (semua layer lain lewat `PlaybackManager`).
- Semua EventChannel memakai `toIntOrElse`/type-filter → NaN/Infinity tick dari
  native tidak bisa crash pipeline posisi/durasi.
- Queue mirror Dart selalu di-resync dari native saat mutasi gagal
  (`_queueMutationGuard` → `syncFromNative`).
- 33 `addListener` ↔ 32 `removeListener` + 1 dialog listener, semua stateful
  widget men-dispose subscription/timer/ticker (synced_lyrics_view,
  player_content, player_song_info_sheet, artwork background, dll).
- Lyrics multi-provider: cancellation token, rate limiter per provider, failure
  TTL 1 jam, upgrade window 2 detik, deadline 15 detik, disk cache TTL 30 hari.
- `HistoryService`/`PlaylistService`/`LyricsSettings` write-through dengan guard.
- `OpenFileService` queued native (`pendingOpenFileUri`) — tidak ada intent hilang
  saat cold start.

## Test gap (Dart)

1. `HistoryService.trackPlay` dengan prefs korup (regresi F6).
2. Konkurensi `ReplayGainService.resolve` + `invalidate` (race in-flight vs remove).
3. `ArtworkRepository.getPath` saat `evict` bersamaan dengan in-flight resolve.
4. `LyricsFetchManager._runParallel` dengan 1 provider lambat + 1 provider cepat.

---

# Bagian 2 — Audit `android/` (Kotlin)

## Scope & metode

- **42 file**, ±14k baris, seluruhnya dibaca penuh (termasuk `MainActivity.kt`
  1.457 baris dan `Media3PlaybackService.kt` 1.996 baris).
- Fokus: race, lifecycle/teardown idempotent, thread-safety lintas thread
  (audio thread ↔ main thread ↔ executor), channel boundary, cache invalidation,
  leak listener/executor.

## Ringkasan eksekutif

Tidak ada **bug terkonfirmasi (P1/P2)** pada jalur produksi. Empat temuan yang
tercatat semuanya **weakness LOW** (satu NIT). Kualitas sangat tinggi — setiap
modul sudah melewati beberapa siklus audit+fix (A1/A2/A3, CE-02..04, CRIT-01,
DE-01..06, DP-1, EQ-02/03, HIGH-01/02, K-02/05, LOW-01/07, MED-01, QS-02/03,
RC-3, SKIP-01, WD-01, ZOOM-01, R-B/R-C 1.5.21, Phase 4.5/9, Item 2/3/6/7/8/10).

## Verifikasi temuan lintas-layer (janji dari Bagian 1, item 3 — fsync failure handling)

- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/replaygain/ReplayGainService.kt`
  — orkestrasi write→close→reopen→verify→(restore) :150, `verifyWriteFd` :197,
  `verifyRemovedFd` :229, `verifyRestoredFd` :236, `restoreRegionFd` :253.
- **Bukti:** setiap mutasi tag berjalan sebagai: tulis → close → buka ulang fd
  baru → verifikasi byte-exact → jika verifikasi gagal, restore region byte-exact
  dari snapshot prior. Kegagalan I/O apa pun (termasuk kondisi yang biasanya
  dipicu fsync: disk penuh, flush tertunda, fd invalid) tidak pernah meninggalkan
  file dalam state rusak — kegagalan verifikasi memicu rollback otomatis.
- **Verdict:** CONFIRMED FIXED — konsisten dengan klaim Bagian 1 item 3.

## Temuan

### K1 (LOW) — `MetadataPrescanner`: race flag `cancelled`/`running` antara `start()` dan `cancel()`

- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/metadata/MetadataPrescanner.kt`
- **Fungsi/baris:** `start()` :47–54 (`cancel()` dulu, `cancelled = false` :52,
  `running = true` :53), loop `if (cancelled) break` :68, `running = false` :112,
  `cancel()` :127–130 (`if (running) { cancelled = true }`).
- **Execution path:** `MainActivity.getSongs()` → `MetadataPrescanner.start()`
  (otomatis setiap refresh library) → Dart `cancelMetadataPrescanner` saat
  playback mulai.
- **Urutan race (reachable):**
  1. Scan A berjalan. `start()` kedua masuk → `cancel()` set `cancelled = true`,
     lalu :52 reset `cancelled = false` dan :53 `running = true`, thread B lahir.
  2. Thread A bangun dari `Thread.sleep`, cek :68 → membaca `cancelled == false`
     (sudah direset oleh `start()` kedua) → **melanjutkan scan penuh**.
  3. Dua scan berjalan paralel — melanggar kontrak dokumentasi "Only one scan may
     run at a time".
  4. Scan A selesai lebih dulu → :112 `running = false` padahal B masih jalan →
     `isRunning` melaporkan salah; `cancel()` berikutnya (saat playback mulai)
     melihat `running == false` → **tidak set `cancelled`** → B terus scan selama
     playback.
- **Counter-evidence:** `MetadataCacheDb.put()` idempotent (key path+mtime), jadi
  tidak ada korupsi data; thread jalan di `THREAD_PRIORITY_LOWEST` sehingga tidak
  starve audio. Dampak = I/O duplikat + cancel kadang tidak efektif.
- **Verdict:** CONFIRMED WEAKNESS (race nyata & reachable; dampak ringan).
- **Severity:** LOW.

### K2 (LOW) — TOCTOU mtime pada `getSongExtendedTags`

- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/MainActivity.kt`
  (handler `"getSongExtendedTags"` :564, `ExoMetadataReader.read` :576,
  `MetadataCacheDb.mtime(path)` :578, `putByPath` :580).
- **Masalah:** mtime di-sample **setelah** read selesai. Jika file berubah di
  antara read dan sampling, tags lama dikunci di bawah mtime baru → lookup
  berikutnya (mtime match) mengembalikan data stale sampai file berubah lagi.
- **Counter-evidence / pembanding:** `getReplayGainTags` dan `getEmbeddedLyrics`
  meng-sample mtime **sebelum** read → arah aman (self-healing). Jendela K2 hanya
  beberapa ms dan hanya tercapai jika file dimodifikasi secara eksternal saat
  metadata executor sedang membaca — bukan jalur yang dihasilkan aplikasi sendiri
  (write ReplayGain memakai fd terpisah dan mtime-nya berubah sebelum read berikutnya).
- **Verdict:** CONFIRMED WEAKNESS. **Severity:** LOW.

### K3 (LOW) — Guard `IS_OVERLAY_PREVIEW` tidak efektif: notifikasi tetap muncul di preview

- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt`
  (`isPreviewMode` :779, baca extra :785, `handlePlayUri` :807, guard :809–810)
  + `transport/TransportCommands.kt` (`handlePlay` → `ensureMediaForeground()` :520).
- **Execution path:** overlay file manager → `NowPlayingOverlayActivity`
  `startService(ACTION_PLAY_URI + IS_OVERLAY_PREVIEW=true)` → `handlePlayUri`
  skip `ensureMediaForeground` (:809–810) → `transportCommands.playNative()` →
  `handlePlay` memanggil `ensureMediaForeground()` **tanpa syarat** (lambda :548
  di service) → notifikasi foreground tetap dibuat di mode preview.
- **Dampak:** menyimpang dari intent desain ("Cuma tampilin notifikasi kalau BUKAN
  dalam mode preview") — preview dari file manager masih memunculkan notifikasi
  media. Bukan crash, bukan state korup.
- **Verdict:** CONFIRMED WEAKNESS (behavior deviation). **Severity:** LOW.

### K4 (NIT) — `NowPlayingOverlayActivity`: future `MediaController` pada retry tidak di-release

- **File:** `android/app/src/main/kotlin/dev/wndavenz/music/NowPlayingOverlayActivity.kt`
  (:172–183 retry loop, :193 hanya future terakhir yang di-`releaseFuture`).
- **Masalah:** setiap retry `connectController()` membuat `ListenableFuture` baru;
  future gagal di antara tidak pernah di-release. Potensi resource leak kecil pada
  koneksi berulang yang gagal (future yang gagal tidak menahan player).
- **Verdict:** NIT — belum terbukti menghasilkan incorrect behavior; hanya
  housekeeping. **Severity:** NIT.

### Catatan lain (bukan temuan)

- `SignalsmithStretchAudioProcessor.getDurationAfterProcessorApplied` memakai
  `speed` target, bukan `appliedSpeed` saat masih ramping — efeknya dapat diabaikan
  (durasi dipakai hanya untuk seek/predict, bukan output audio).
- `CrossfadeTimelineLogger.begin/end` race pada epoch — didokumentasikan dan
  disengaja untuk tool diagnostik.

## Verified strengths (Kotlin)

- **ReplayGain:** protocol write→close→reopen→verify→(restore) lengkap
  (`ReplayGainService.kt`); `MetadataCacheDb` keyed path+mtime dengan `pruneOld()`
  dan `invalidate(songId)`; `MediaStoreWriteGate` matrix per API level;
  `openReplayGainWriteFd` catch lengkap → null aman (gagal = deny, bukan crash).
- **MainActivity:** bounded executor + `AbortPolicy` + `onRejected` per channel;
  `postToFlutter` diguard `shuttingDown`; A2 — artwork cache dihapus pada song
  delete di semua path API; `songsToJson` single-pass; `pendingOpenFileUri`
  cold-start drain via `getInitialUri` + invoke best-effort.
- **NativePaletteBridge:** coalescing per songId (in-flight job), exactly-once
  via `AtomicBoolean`, watchdog callback 5 s, `dispose()` sebelum executor
  di-shutdown, metrics bounded.
- **ArtworkCacheManager:** lock registry process-wide (dua instance Activity +
  service berbagi dir), atomic tmp+rename, `isUsableCacheFile` bounds-check,
  LRU throttle 15 s, cleanup melindungi songId in-flight (anti TOCTOU),
  `delete()` untuk song yang dihapus.
- **Pipeline artwork (FallbackBitmapLoader / SessionArtworkProvider /
  PlaybackNotificationManager):** two-pass decode cap 1024, letterbox square,
  negative cache TTL 30 s, per-key generation + `inFlightLoads` → tidak ada stale
  post lintas track, `close()` idempotent + guard `closed`.
- **Media3PlaybackService:** de-dupe listener via `IdentityHashMap`;
  attach/detach simetris (stats/stereo/stretch/mime cleanup); teardown idempotent
  via `ServiceShutdownCoordinator` + `ServiceReadyGate`; LOW-07 swap offload
  listener (tanpa akumulasi); publish artwork session dengan guard
  (`p === activePlayer && mediaId match`); `forEachLivePlayer` identity-based.
- **TransportCommands:** SKIP-01 rapid-skip throttle; `restoreQueueAfterCrossfadeCancel`
  mencegah 1-item timeline lock di pause/skip/settings; tanpa trailing `emitAll()`
  (DE-01..06); clamp speed (0.25–4) & pitch (0.5–2); `getAudioFormat` /
  `getPlaybackSnapshot` null-safe.
- **CrossfadeController:** isolasi prefix+tail player lama (anti wrap ke queue[0]
  saat VBR imprecision); equal-power fade; CE-04 `cancel(resetVolume)`; abort
  guard bila active player berubah mid-fade; `stampDual` di setiap titik kritis.
- **PreloadManager:** guard `current.mediaItemCount < queue.size` mencegah
  `nextMediaItemIndex` temporer (1-item promotion) menimpa `preloadedQueueIndex`.
- **AudioOffloadManager:** observer-only sesuai Media3 1.10.1 (API scheduling
  dihapus — terdokumentasi, no-op eksplisit).
- **StereoWidening / Signalsmith:** `volatile` matrix, `NOT_SET` bypass,
  fail-open, EOS flush, bypass-ring prime saat bypass→STFT, `onFlush`/`onReset`
  bersih (destroy handle, reset counter).
- **QueueSync:** coalescing single-thread + `AtomicReference` (LOW-01); snapshot
  queue di-capture di main thread (ExoPlayer state tidak dibaca off-thread).

## Test gap (Kotlin)

1. Race `MetadataPrescanner` (K1) — uji konkurensi `start()`+`cancel()` berulang
   sambil mengamati `isRunning`.
2. `MediaStoreWriteGate` batch grant saat user menolak dialog (parsial grant).
3. Crossfade dengan `REPEAT_MODE_ONE` + skip cepat (edge wrap ke track sama).
4. `NowPlayingOverlayActivity` — koneksi service gagal berulang (retry backoff,
   device test).

---

*Audit selesai: `lib/` (277 file Dart) + `android/` (42 file Kotlin). Tidak ada
kode yang diubah oleh audit ini.*
