# Bit-Perfect (Clean Player) Audit — 2026-08-15

## Scope

Audit read-only terhadap jalur **Bit-Perfect Mode** (player "clean"):

- `Media3PlaybackService.kt` — `createBitPerfectPlayer()` (:1339), `setBitPerfectMode()` (:1972),
  `switchToBitPerfectPlayer()` (:1982), `switchFromBitPerfectPlayer()` (:2030),
  listener guard efek (:1556-1562), `forEachLivePlayer()` (:2082),
  `attachOffloadListenerTo()` (:815), audioCapReceiver (:643-657),
  sleep-timer cancel branch di `onMediaItemTransition` (:1483-1498).
- `AudioEffectsManager.kt` — guard `lastAttachedSessionId` (:75-84), `releaseEffects()` (:199),
  `resetAndReattach()` (:220).
- `QueueManager.kt` — `setQueue()` (tidak menyentuh repeat/shuffle).
- `TransportState.kt` — position ticker → `maybeCrossfadeOut()`.
- `PreloadManager.kt` — `preloadNextTrack()` / `ensureStandbyPlayer()` (memakai ulang player
  slot standby = `preBitPerfectPlayer`).
- `TransportCommands.kt` — dispatch `setBitPerfectMode` (:135), `setCrossfadeDuration`.
- Dart: `AudioEffectsService.setBitPerfectMode()` / `_snapshotBeforeBitPerfect()` /
  `_forceBypassEverything()` / `_restoreFromBitPerfectSnapshot()`,
  `BitPerfectLock` (cakupan lock UI), `_BitPerfectSection` (settings toggle).

**Tidak ada kode produksi yang diubah.** Verifikasi statis (tidak ada Android SDK di
environment; konsisten dengan audit-audit sebelumnya).

## Ringkasan eksekutif

Konstruksi clean player sudah benar: `DefaultAudioProcessorChain()` kosong, float output
dimatikan, tidak terdaftar ke `StereoWidthManager`/`StretchManager`, efek AudioFlinger
di-guard agar tidak pernah attach ke session-nya, buffer 15s/50s/1.5s/3s, wake lock,
decoder fallback, dan artwork metadata disabled. Sisi Dart juga rapi: snapshot + force-bypass
semua fitur processing (persisted), restore saat keluar, dan lock UI menyeluruh.

Namun ada **1 temuan P1 dan 3 temuan P2** yang semuanya berpusat pada **transisi masuk/keluar
mode**, bukan pada player-nya sendiri:

1. **P1 — Keluar mode tidak mengembalikan efek**: `attachEffects(sid)` di `switchFromBitPerfectPlayer`
   di-skip oleh guard `lastAttachedSessionId` (session sama persis dengan sebelum masuk mode,
   karena `releaseEffects()` tidak me-reset guard). EQ/BassBoost/LoudnessEnhancer mati sampai
   ada perubahan session (ganti perangkat output / service restart).
2. **P2 — repeatMode & shuffle hilang selama mode**: `queueManager.setQueue()` tidak menyalin
   repeat/shuffle ke clean player (default OFF). Repeat-one/all + shuffle diam-diam tidak
   berlaku selama bit-perfect aktif.
3. **P2 — audioCapReceiver dapat menempelkan efek ke clean player**: pergantian output
   (BT/HDMI) saat mode aktif memanggil `resetAndReattach(activePlayer.sessionId)` tanpa guard
   `bitPerfectModeOn` → EQ menyala di tengah "bit-perfect".
4. **P2 — End-of-song sleep timer bisa tercancel oleh toggle ON**: `setQueue` pada clean player
   yang baru memicu `onMediaItemTransition(PLAYLIST_CHANGED)` → branch cancel timer.
   (Perlu device test untuk konfirmasi.)

Plus 3 weakness P3 (offload listener tidak dimigrasi, mutual-eksklusivitas crossfade hanya
dijaga sisi Dart, restart tidak mengaktifkan clean player secara native).

---

## Findings

### BP-01 (P1) — Keluar Bit-Perfect Mode tidak mengembalikan EQ/BassBoost/LoudnessEnhancer

**Verdict: Confirmed bug** (statis, jalur produksi).

**Evidence**
- `Media3PlaybackService.kt:2061-2062` (`switchFromBitPerfectPlayer`):
  `val sid = restored.audioSessionId; if (sid > 0) effectsManager.attachEffects(sid)`
- `AudioEffectsManager.kt:75-84` — guard `attachEffects`:
  `if (sessionId == lastAttachedSessionId) { log skip; return }`
- `AudioEffectsManager.kt:199-207` — `releaseEffects()` **tidak** me-reset `lastAttachedSessionId`
  (komentar eksplisit: "It is reset in the guard at the top of attachEffects when a new session
  arrives" — komentar itu keliru: guard *return* saat session sama, tidak me-reset).
- `AudioEffectsManager.kt:220-222` — satu-satunya jalur reset eksplisit adalah `resetAndReattach()`,
  yang hanya dipanggil oleh audioCapReceiver (:654), bukan oleh jalur bit-perfect.

**Failure sequence**
1. Efek ter-attach ke session X (player primary) → `lastAttachedSessionId = X`.
2. User mengaktifkan bit-perfect → `switchToBitPerfectPlayer` memanggil `releaseEffects()` —
   objek efek di-release, `lastAttachedSessionId` tetap X.
3. Clean player aktif dengan session Y (guard :1561 mencegah attach ke Y — benar).
4. User menonaktifkan → `restored` = player primary, session-nya masih X (audioSessionId
   stabil per instance ExoPlayer, tidak berubah oleh pause/prepare).
5. `attachEffects(X)` → guard `X == lastAttachedSessionId` → **skip**. EQ/BassBoost/
   LoudnessEnhancer tidak dibuat. `equalizer` tetap null.
6. Dart lalu re-push setting (`_restoreFromBitPerfectSnapshot` → `setEqualizerEnabled(true)` +
   `restoreEqualizerBands`), tetapi native hanya menyimpan state (`eqEnabled`/`bandGains`);
   semua setter terhadap `equalizer == null` adalah silent no-op.

**Impact**
Setelah keluar bit-perfect, EQ (dan bass/loudness) tidak terdengar sampai session berubah —
mis. pergantian perangkat output (yang kebetulan memicu `resetAndReattach`) atau service
restart. Ini melanggar kontrak "toggle keluar harus mulus" dan akan gagal pada device test
"Bit-Perfect toggle (masuk/keluar mode harus mulus)".

**Recommendation**
Ganti `effectsManager.attachEffects(sid)` dengan `effectsManager.resetAndReattach(sid)` di
`switchFromBitPerfectPlayer` (atau reset `lastAttachedSessionId` sebelum `attachEffects`).
Tambahkan test device: EQ nyala → toggle ON → OFF → EQ harus terdengar kembali.

---

### BP-02 (P2) — repeatMode & shuffleMode tidak ditransfer ke clean player

**Verdict: Confirmed bug** (statis).

**Evidence**
- `Media3PlaybackService.kt:2012-2014` (`switchToBitPerfectPlayer`):
  `queueManager.setQueue(queueManager.queue, queueManager.activeQueueIndex, positionMs)`
- `QueueManager.kt` `setQueue()` — hanya `setMediaItems(...)` + `prepare()`; tidak menyentuh
  `repeatMode`/`shuffleModeEnabled`. Clean player baru memiliki default `REPEAT_MODE_OFF`,
  `shuffleModeEnabled = false`.
- Pembanding: `restoreQueueFromPrefs()` (:1956-1957) **eksplisit** menyalin
  `p.repeatMode`/`p.shuffleModeEnabled` setelah `setQueue` — jalur bit-perfect tidak melakukannya.

**Impact**
Selama bit-perfect aktif, repeat-one/repeat-all/shuffle diam-diam nonaktif (track berhenti di
akhir queue alih-alih loop; repeat-one + end-of-song sleep timer tidak berperilaku seperti
biasanya). Saat keluar, `preBitPerfectPlayer` masih menyimpan setting lama, jadi pulih
otomatis — tetapi selama mode, perilaku salah. UI transport repeat tetap bisa diubah user
(lock hanya menutup bagian audio settings), jadi user bisa "memperbaiki" manual tanpa sadar
ini bukan bug dirinya.

**Recommendation**
Setelah `setQueue` di `switchToBitPerfectPlayer`, salin state lama:
`clean.repeatMode = current.repeatMode; clean.shuffleModeEnabled = current.shuffleModeEnabled`
(sebelum `clean.play()`). Untuk simetri, salin juga saat keluar (walaupun `preBitPerfectPlayer`
umumnya masih benar).

---

### BP-03 (P2) — AudioCapabilitiesReceiver dapat meng-attach efek ke clean player

**Verdict: Confirmed bug** (statis, reachable).

**Evidence**
- `Media3PlaybackService.kt:643-657` — audioCapReceiver (BT connect/disconnect, HDMI):
  `handler.postDelayed({ effectsManager.resetAndReattach(activePlayer?.audioSessionId) }, 500L)`
  tanpa guard `bitPerfectModeOn`.
- `Media3PlaybackService.kt:645-646` — `forEachLivePlayer { p -> ... }` hanya mencakup
  primary + secondary (:2082-2086), mengecualikan `bitPerfectPlayer` untuk track re-selection.

**Failure sequence**
1. Bit-perfect aktif; active player = clean (session Y); `lastAttachedSessionId = X` (lama).
2. User colok/cabut headphone BT (atau HDMI) → `audioCapReceiver` callback.
3. `resetAndReattach(Y)` → reset guard → `attachEffects(Y)` → **Equalizer/BassBoost dibuat
   pada session clean player**. Efek terdengar di tengah mode yang diklaim bebas-proses.

**Impact**
Violasi langsung invariant "no AudioEffects during bit-perfect"; suara berubah tanpa tindakan
user. Catatan: efek samping "positif" — `lastAttachedSessionId` menjadi Y, sehingga BP-01
kebetulan tersembuhkan jika device change terjadi selama mode.

**Recommendation**
Guard `bitPerfectModeOn` di callback audioCapReceiver (skip `resetAndReattach` saat mode
aktif). Pertimbangkan juga memasukkan `bitPerfectPlayer` ke `forEachLivePlayer` untuk
track re-selection (atau dokumentasikan kenapa tidak).

---

### BP-04 (P2) — End-of-song sleep timer dapat tercancel oleh toggle bit-perfect ON

**Verdict: Confirmed-reachable (statis), wajib device test.**

**Evidence**
- `Media3PlaybackService.kt:1483-1498` — `onMediaItemTransition`:
  reason `SEEK`/`PLAYLIST_CHANGED` + `sleepTimerActive` + `sleepEndOfSong` → `sleepTimerManager.cancel()`.
- `switchToBitPerfectPlayer` (:2000-2014): clean player baru dibuat, listener di-attach
  (:2002), lalu `queueManager.setQueue(...)` → `setMediaItems` pada player fresh memicu
  `onMediaItemTransition(reason = PLAYLIST_CHANGED)` saat timeline kosong → item pertama.

**Failure sequence**
1. User mengaktifkan sleep timer **end-of-song** (berhenti di batas lagu).
2. User masuk Settings → toggle bit-perfect ON (bukan operasi "user skip", queue tidak
   berubah isinya).
3. `setQueue` pada clean player memicu transisi PLAYLIST_CHANGED → timer di-cancel diam-diam.
4. Lagu berakhir tanpa stop; timer sudah tidak aktif.

**Impact**
Sleep timer end-of-song hilang tanpa pemberitahuan ketika user men-toggle bit-perfect —
kombinasi fitur yang sangat mungkin dipakai bersamaan (mode malam + kualitas maksimal).

**Recommendation**
Jangan perlakukan toggle bit-perfect sebagai "user skip": beri pengecualian di branch cancel
(skip cancel saat `bitPerfectModeOn` di jalur switch internal), atau re-arm timer setelah
switch selesai. Konfirmasi dengan device test: arm end-of-song → toggle ON → verifikasi timer
masih aktif.

---

### BP-05 (P3) — Offload listener tidak dimigrasi saat bit-perfect switch

**Verdict: Confirmed weakness** (doc/behavior mismatch, impact rendah).

**Evidence**
- `Media3PlaybackService.kt:1295` — komentar: "attached whenever the active player changes
  (onCreate, onCrossfadeComplete, **bit-perfect switches**)".
- `attachOffloadListenerTo` hanya dipanggil di `onCreate` (:248) dan `onCrossfadeComplete`
  (:489). `switchToBitPerfectPlayer`/`switchFromBitPerfectPlayer` **tidak** memanggilnya.

**Impact**
Selama bit-perfect, listener tetap menempel di `preBitPerfectPlayer` (yang sedang pause) —
kebetulan benar saat keluar karena player itu menjadi aktif lagi. Namun active player (clean)
tidak punya offload listener, dan OS grant/reject yang masuk selama mode dilaporkan terhadap
player yang salah (event `offloadState` bisa stale). Dampak praktis rendah: offload scheduling
dimatikan dan crossfade nonaktif selama mode.

**Recommendation**
Panggil `attachOffloadListenerTo(clean)` pada enter dan `attachOffloadListenerTo(restored)`
pada exit, atau perbaiki komentar :1295.

---

### BP-06 (P3) — Mutual eksklusivitas crossfade vs bit-perfect hanya dijaga sisi Dart

**Verdict: Confirmed weakness / hardening** (tidak aktif di flow UI saat ini).

**Evidence**
- Dart `_forceBypassEverything()` memanggil `setCrossfade(0.0)` sebelum native switch, dan
  `BitPerfectLock` mengunci kontrol crossfade — jadi di flow normal `crossfadeDurationSec == 0`
  selama mode.
- Native tidak punya guard `bitPerfectModeOn` di: `TransportState` ticker →
  `maybeCrossfadeOut()` (TransportState.kt:74-85), `onPlaybackStateChanged` STATE_READY →
  `preloadNextTrack()` (:1332-1334), maupun `PreloadManager.preloadNextTrack()`.
- Jika `crossfadeDurationSec > 0` entah bagaimana selama mode (nilai prefs lama, sync
  pengaturan, perubahan UI masa depan): `ensureStandbyPlayer()` mengambil slot standby =
  `preBitPerfectPlayer` (karena `activePlayer === bitPerfectPlayer`) lalu
  `preloadNextTrack` memanggil `standby.clearMediaItems()` — **queue preBitPerfectPlayer
  terhapus** — dan di akhir lagu `beginCrossfade` mempromosikan player DSP + `onCrossfadeComplete`
  re-attach efek. Ditambah `switchFromBitPerfectPlayer` membaca `wasPlaying`/`positionMs` dari
  clean player yang sudah idle → exit menghentikan playback di posisi stale.

**Impact**
Invariant "Bit-Perfect dan dual-player crossfade saling eksklusif" dijamin hanya oleh satu
lapisan (Dart). Pelanggaran menghasilkan state exit yang rusak (playback berhenti, posisi
salah, efek re-attach tanpa sepengetahuan UI).

**Recommendation**
Tegakkan di native: guard `bitPerfectModeOn` di awal `maybeCrossfadeOut()` (dan di
`preloadNextTrack` / READY-preload). Di `switchFromBitPerfectPlayer`, baca `wasPlaying` /
`positionMs` dari **active player sebenarnya** (bukan clean) bila active player telah berubah.

---

### BP-07 (P3) — Restart dengan bitPerfectMode=true tidak mengaktifkan clean player native

**Verdict: Confirmed weakness** (state desync, dampak audio ≈ nihil).

**Evidence**
- `AudioEffectsService.init()` (:218) mengembalikan `bitPerfectMode.value` dari prefs — UI ON.
- Tidak ada panggilan `PlaybackManager.setBitPerfectMode(true)` saat startup; native service
  baru selalu `bitPerfectModeOn = false` dengan pipeline normal.

**Impact**
Setelah proses mati + restart (START_STICKY / kill), UI menampilkan "Bit-Perfect Mode: ON"
dan mengunci kontrol, tetapi native menjalankan pipeline dual-player biasa. Secara audibel
hampir identik karena semua processing tersimpan off (EQ off, crossfade 0, dst.), tapi
invariant "clean player + zero AudioEffects" tidak dihormati, status native tidak sinkron
dengan UI, dan temuan BP-02 justru *tidak* terjadi di jalur ini (repeat/shuffle jalan normal
di primary player). Inkonsistensi perilaku antara "toggle langsung" vs "restart" itu sendiri
adalah bug konsistensi.

**Recommendation**
Saat startup, jika `bitPerfectMode` persist true, jalankan `PlaybackManager.setBitPerfectMode(true)`
setelah service siap (atau persist `bitPerfectModeOn` native dan restore).

---

## Verifikasi ulang (turn ini) — semua klaim di-check terhadap code aktual + Media3 1.11.0 source

Setiap finding di atas diverifikasi ulang statis terhadap working tree saat ini. Hasil:

| Finding | Status | Bukti kunci tambahan |
|---|---|---|
| BP-01 | ✅ CONFIRMED | Guard `sessionId == lastAttachedSessionId` di `attachEffects` (AudioEffectsManager.kt) → return sebelum `releaseEffects()`. `releaseEffects()` tidak me-reset guard. `switchFromBitPerfectPlayer` memanggil `attachEffects(restored.audioSessionId)`; session id ExoPlayer stabil per instance (dibangkitkan sekali oleh DefaultAudioSink, dipertahankan saat AudioTrack di-recreate), jadi `sid == lastAttachedSessionId` pada jalur normal → skip. Dart `_restoreFromBitPerfectSnapshot` → `setEqualizerEnabled(true)` → native `equalizer == null` → state disimpan, silent no-op. |
| BP-02 | ✅ CONFIRMED | `QueueManager.setQueue()` (queue/QueueManager.kt:44-55) hanya `setMediaItems`+`prepare()`; kontras eksplisit `restoreQueueFromPrefs()` (Media3PlaybackService.kt:1956-1957) yang menyalin `repeatMode`/`shuffleModeEnabled`. |
| BP-03 | ✅ CONFIRMED | audioCapReceiver (kt:643-657): `handler.postDelayed({ resetAndReattach(activePlayer?.audioSessionId) }, 500L)` tanpa guard `bitPerfectModeOn`. `forEachLivePlayer` (kt:2085-2089) hanya primary+secondary. |
| BP-04 | ✅ CONFIRMED (statis) | Media3 `ExoPlayerImpl.evaluateMediaItemTransitionReason` (release branch): `newTimeline.isEmpty() != oldTimeline.isEmpty()` → `MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED`. Clean player fresh (timeline kosong) + `setQueue` → transisi PLAYLIST_CHANGED nyata. `isActiveEvent()` (`p === activePlayer`) lolos karena `activePlayer = clean` di-set sebelum `setQueue`. Catatan: synthetic `onMediaItemTransition` dari `ActivePlayerProxy.switchTo` (kt:104) TIDAK kena branch ini (listener service terdaftar langsung di ExoPlayer, bukan di proxy). Device test tetap disarankan untuk konfirmasi runtime. |
| BP-05 | ✅ CONFIRMED | `attachOffloadListenerTo` hanya dipanggil di onCreate (:248) dan onCrossfadeComplete (:489); komentar :1295 mengklaim "bit-perfect switches" — tidak benar. |
| BP-06 | ✅ CONFIRMED (hardening) | `maybeCrossfadeOut` (CrossfadeController.kt:116) guard `crossfadeDurationSec <= 0f`; `standbyPlayer()` (kt:85-86) saat `activePlayer === bitPerfectPlayer` mengembalikan `primaryPlayer` = `preBitPerfectPlayer`. Tidak reachable di flow normal (Dart force-bypass men-set crossfade 0 sebelum switch). |
| BP-07 | ✅ CONFIRMED | `AudioEffectsService.init()` (:218) set notifier dari prefs; satu-satunya caller native `setBitPerfectMode` adalah toggle UI (:906/:914) yang early-return saat nilai sama. Toggle OFF setelah restart = native no-op (`if (!bitPerfectModeOn) return`). |

## Temuan tambahan turn ini

### BP-08 (P3) — Dispatch `setBitPerfectMode` sebelum guard not-ready (desync silent)

- `TransportCommands.kt:135-140` menangani `"setBitPerfectMode"` SEBELUM guard `getPlayer() ?: result.error("not_ready")` (:143).
- Jika Dart men-toggle saat engine belum siap (race startup): `switchToBitPerfectPlayer` → `val current = activePlayer ?: return` → silent return, `bitPerfectModeOn` tetap false, TAPI Dart sudah set notifier=true + persist prefs.
- Dampak: UI ON, native normal — desync yang sama dengan BP-07, window sempit (hanya sebelum service siap).
- Rekomendasi: pindahkan dispatch ke belakang guard not-ready, atau kembalikan notifier bila native menolak.

### BP-09 (Note) — Volume per-player tidak ditransfer antar player

- `switchTo` (ActivePlayerProxy) tidak menyalin `volume`; clean player lahir dengan volume 1.0.
- Dampak praktis rendah: tidak ada slider volume in-app — `PlaybackManager.setVolume` tidak punya caller di `lib/` (volume lewat system media volume, device-global). Satu-satunya jalur `player.volume != 1.0` adalah fade (play/pause fade, sleep fade, crossfade) — dan semua di-cancel/restore pada jalur enter (`crossfadeController.cancel(resetVolume=true)`, pause → `cancelFadeOnly`). Edge: toggle di tengah play/pause fade → clean mulai di 1.0 sementara primary masih mid-ramp (pop kecil, 1×).
- Verdict: note, bukan bug.

### Nuansa BP-07 — preamp native tidak di-force-bypass

- `_forceBypassEverything()` tidak menyentuh `nativePreampDb` (preamp bukan bagian snapshot `bpmSnap*`), dan `setNativeGainBypass(true)` tidak dipersist. Setelah restart, `nativeGainBypass` = false → preamp non-zero tetap apply di primary player.
- Dampak: bit-perfect pasca-restart tidak murni bila user punya preamp ≠ 0 (niche). Selebihnya klaim doc tetap benar (EQ/RG/LN/crossfeed/compressor/limiter/clipper ter-persist off).

## Verified strengths

- `createBitPerfectPlayer()` (:1339-1402) benar-benar bersih: `DefaultAudioProcessorChain()`
  kosong (tanpa NativeDsp/StereoWiden/Stretch/ToFloat/ToInt16), float output dimatikan,
  tidak didaftarkan ke `StereoWidthManager`/`StretchManager`, buffer 15s/50s/1.5s/3s dengan
  `setPrioritizeTimeOverSizeThresholds(true)`, wake lock, `EXTENSION_RENDERER_MODE_PREFER` +
  decoder fallback, artwork metadata disabled, seek increments 10s/30s, audio attributes
  media/music + `setHandleAudioBecomingNoisy(false)`.
- Guard efek di `onAudioSessionIdChanged` (`p !== bitPerfectPlayer`, :1560) mencegah efek
  menempel ke clean player pada jalur normal.
- Crossfade di-cancel + standby di-release **sebelum** switch; queue/posisi di-rebuild pada
  clean player via `setQueue(..., posMs)`.
- `releaseBitPerfectPlayer` ter-wire ke `ServiceShutdownCoordinator` (:679-681, teardown
  :124) dan `onDestroy` membersihkan semua field bit-perfect (:980-982) — STOP/engine-switch
  selama mode aman.
- Sisi Dart: snapshot semua setting processing (`bpmSnap*`, persisted), force-bypass
  menyeluruh termasuk ReplayGain/Gain stage, restore penuh saat keluar, lock UI
  (`BitPerfectLock`) menutup EQ, ReplayGain, Loudness Norm, Crossfeed, Crossfade,
  Compressor, Limiter, Soft Clipper, Bass Boost, Speed, Pitch — plus konfirmasi dialog
  sebelum enable.
- State efek (`eqEnabled`, `bandGains`, `loudnessTargetMb`, `bassBoostStrength`) bertahan
  melewati `releaseEffects()`; begitu re-attach dipicu (session baru), setting user terpasang.

## Test gap (device — Xiaomi Mi 9T/MIUI 12)

1. **BP-01**: EQ nyala (gain terasa) → toggle bit-perfect ON → OFF → verifikasi EQ kembali
   terdengar. (Prediksi: GAGAL di kode saat ini.)
2. **BP-02**: repeat-one aktif → toggle ON → biarkan lagu berakhir → verifikasi loop repeat-one.
   (Prediksi: tidak loop.)
3. **BP-03**: bit-perfect ON → colok/cabut headphone BT (atau HDMI) → verifikasi tidak ada
   efek yang muncul; cek log "attachEffects" di Log Viewer.
4. **BP-04**: arm sleep timer end-of-song → toggle bit-perfect ON → verifikasi timer tidak
   tercancel.
5. **BP-06 (regression)**: crossfade 8s → toggle ON → verifikasi `crossfadeDuration` menjadi 0
   dan tidak ada standby player dibuat (log Preload/Crossfade).
6. **BP-07**: bit-perfect ON → kill app (recents swipe) → relaunch → verifikasi UI mode &
   pipeline native konsisten (dan toggle OFF mengembalikan EQ).
7. STOP di tengah bit-perfect → notifikasi hilang, service mati, mini player exit; play lagu
   baru harus normal (regresi fix STOP).

## Verification

- `git diff --check`: tidak ada perubahan kode — audit read-only.
- Kotlin: verifikasi statis (tanpa Android SDK; `./gradlew :app:compileDebugKotlin` tidak
  dapat dijalankan di environment ini, sama seperti audit sebelumnya).
- Dart: tidak ada perubahan → tidak perlu `flutter analyze`.
- Tidak ada runtime Mi 9T/MIUI 12 validation di environment ini.

## Kesimpulan

Clean player-nya sendiri sudah benar dan selaras dengan dokumentasi. Semua masalah berada di
**transisi**: (1) exit tidak mengembalikan efek karena guard `lastAttachedSessionId` — ini yang
paling urgent; (2) repeat/shuffle hilang selama mode; (3) device-output change bisa
menyuntikkan efek ke clean player; (4) sleep timer end-of-song bisa tercancel oleh toggle.
Perbaikan pertama (BP-01) kecil dan lokal (`resetAndReattach`), dan BP-02/BP-03 masing-masing
hanya 1-2 baris guard/copy state. BP-04 dan BP-06 perlu device test sebelum diputuskan.

---

## Status: FIXED (2026-08-16) — BP-01 s/d BP-08 diperbaiki

Semua finding produksi (BP-01..BP-08) sudah diperbaiki. BP-09 tetap note (bukan bug).

| Finding | Fix | File / lokasi |
|---|---|---|
| **BP-01** | `effectsManager.attachEffects(sid)` → `effectsManager.resetAndReattach(sid)` di `switchFromBitPerfectPlayer` — guard `lastAttachedSessionId` di-bypass, EQ/BassBoost/LoudnessEnhancer ter-attach penuh saat keluar mode. | `Media3PlaybackService.kt` `switchFromBitPerfectPlayer()` (±2110-2118) |
| **BP-02** | Salin `repeatMode`/`shuffleModeEnabled` dari `current` ke `clean` setelah `setQueue` (enter), dan dari `clean` ke `restored` (exit, simetri). | `Media3PlaybackService.kt` switchTo (±2044-2046) / switchFrom (±2103-2105) |
| **BP-03** | audioCapReceiver: `resetAndReattach` hanya jika `!bitPerfectModeOn`. `forEachLivePlayer` kini mencakup `bitPerfectPlayer` (track re-selection saat ganti output device). | `Media3PlaybackService.kt` :661-668 (receiver), `forEachLivePlayer` (±2140-2143) |
| **BP-04** | Field `bitPerfectSwitching` + try/finally di kedua switch; branch cancel sleep-timer menambahkan `!bitPerfectSwitching` — transisi internal (timeline kosong → queue) tidak membatalkan timer end-of-song; user skip di luar window tetap cancel. | `Media3PlaybackService.kt` :101 (field), :1504-1513 (cancel), :2012/2075 (flag) |
| **BP-05** | `attachOffloadListenerTo(clean)` pada enter dan `attachOffloadListenerTo(restored)` pada exit — listener offload dilaporkan terhadap player yang benar selama mode. | `Media3PlaybackService.kt` switchTo (±2050) / switchFrom (±2107) |
| **BP-06** | `CrossfadeController` param baru `isBitPerfectModeActive` (di-wire `{ bitPerfectModeOn }`) + guard di `maybeCrossfadeOut()`; guard `!bitPerfectModeOn` di preload READY; `switchFromBitPerfectPlayer` membaca state exit dari active player sebenarnya (defensive). | `CrossfadeController.kt` :79-84/:120-122; `Media3PlaybackService.kt` :521-527 (wiring), :1450-1456 (READY) |
| **BP-07** | `_pushEngineSettingsWhenReady()`: jika `bitPerfectMode.value` true setelah `waitForServiceReady()` → `PlaybackManager.setBitPerfectMode(true)` — pipeline native tersinkron dengan UI setelah restart/kill. | `lib/services/audio/audio_effects_service/service.dart` :276-288 |
| **BP-08** | Dispatch `setBitPerfectMode` dipindah ke belakang guard not-ready di `TransportCommands` → toggle dini mendapat `not_ready` dan `Media3PlaybackBridge._invoke` me-retry (bukan silent no-op). | `TransportCommands.kt` :143-154 |
| Nuansa BP-07 (preamp) | Preamp masuk snapshot (`bpmSnapPreamp`); `_forceBypassEverything` → `setNativePreampDb(0.0)` (persist, bukan hanya bypass live); restore memakai nilai snapshot. | `service.dart` :942, :962-967, :1003-1007 |

Verifikasi: `dart analyze lib` → **No issues found**; `git diff --check` → bersih; 4 file source berubah
(+163/-78). Kotlin: review statis penuh (tanpa Android SDK). Device test tetap disarankan untuk
konfirmasi runtime BP-01/BP-03/BP-04/BP-07 (lihat Test gap di atas).
