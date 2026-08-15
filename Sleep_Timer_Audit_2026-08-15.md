# Sleep Timer Audit — 2026-08-15

## Scope

Audit read-only menyeluruh terhadap fitur **Sleep Timer** (Dart UI adapter + native
`SleepTimerManager` di Media3PlaybackService). Tidak ada kode produksi yang diubah.

Surface yang diaudit:

- Dart: `lib/services/sleep_timer_service.dart`, `lib/pages/settings/sleep_timer_page*.dart`,
  `lib/widgets/player/player_more_menu.dart`, `lib/services/audio_service/service.dart`,
  `lib/services/audio/media3/media3_playback_bridge.dart`, `lib/services/audio_playback_state.dart`
- Kotlin: `sleep_timer/SleepTimerManager.kt`, `Media3PlaybackService.kt`,
  `transport/TransportCommands.kt`, `transport/TransportState.kt`,
  `crossfade/CrossfadeController.kt`, `transport/PlayPauseFadeController.kt`,
  `MainActivity.kt`, `ServiceShutdownCoordinator.kt`

Verdict skala: **Confirmed bug** / **Confirmed weakness** / **False positive** / **Runtime-only**.

## Fix status (2026-08-15)

F1, F2, dan F3 **sudah diperbaiki** di turn ini (verifikasi statis; Kotlin tidak
bisa dikompilasi di environment ini — tanpa Android SDK).

- **F1 → FIXED** — `CrossfadeController` mendapat param `isEndOfSongSleepTimerActive`
  (`CrossfadeController.kt:78-81`) dan guard di `maybeCrossfadeOut()` (`:118-126`):
  selama end-of-song armed, crossfade tidak pernah dimulai → lagu berjalan ke akhir
  alami → trigger `STATE_ENDED`/AUTO-transition yang sudah ada bekerja (termasuk
  repeat-all). Di-wire dari `Media3PlaybackService.kt:514-519`.
  - Catatan: kasus **repeat-one** + end-of-song (loop native dengan reason `REPEAT`)
    adalah batasan pre-existing yang TIDAK diperbaiki di turn ini (blok
    `onMediaItemTransition` berada di luar jangkauan edit aman). Fix satu baris:
    sertakan `MEDIA_ITEM_TRANSITION_REASON_REPEAT` pada kondisi fire, dan
    eksklusikan dari kondisi cancel (ganti `reason != AUTO` menjadi
    `reason == SEEK || reason == PLAYLIST_CHANGED`).
- **F2 → FIXED** — `SleepTimerManager.startFadeOut` kini selalu mengarah ke player
  yang di-capture, bukan `getPlayer()` per-tick; guard baru `isCrossfadeActive()`
  (`SleepTimerManager.kt:31-36`, di-wire `Media3PlaybackService.kt:356-357`)
  mencegah race volume dengan `runEqualPowerFade`; swap player / crossfade aktif →
  pause player yang sedang bersuara + `finishFade()` (`:186-196`).
  `TransportCommands.handlePlay`/`handlePause` memanggil `cancelFadeOnly()`
  (`:503-508, 540-544`) → play di tengah fade tidak lagi dibatalkan fade-nya dan
  timer armed tidak tersentuh. State `fading` baru diekspos via event
  (`"fading"` key) + `SleepTimerService.isFading` + kartu aktif menampilkan
  "Fading out…" dengan tombol cancel yang tetap berfungsi selama 20 detik.
- **F3 → FIXED** — `SleepTimerManager.release()` (`:268-280`) meng-emit
  `{active:false}` bila timer/fade sedang aktif saat service dihancurkan;
  safety net Dart di `AudioService.syncFromNative()` (`service.dart:778-788`):
  snapshot null (service mati) → `SleepTimerService.resetToInactive()` +
  `AudioPlaybackState` di-reset. Timer tidak bisa hidup di luar service, jadi
  reset ini selalu benar.


## Arsitektur (ringkas)

```
UI (sheet / full page)
  → SleepTimerService.startDuration / startEndOfSong / cancel   (optimistic set + unawaited)
  → Media3PlaybackBridge.setSleepTimer / setSleepTimerEndOfSong / cancelSleepTimer
  → MethodChannel "media3PlaybackChannel"
  → TransportCommands.dispatch ("setSleepTimer" | "setSleepTimerEndOfSong" | "cancelSleepTimer")
  → SleepTimerManager (Handler main-looper, hidup di dalam Media3PlaybackService)
      • startDuration  → tick 1s (emit remainingMs) + stop runnable di durationMs
      • startEndOfSong → hanya flag; fire point di onMediaItemTransition(AUTO) / STATE_ENDED
      • triggerStop    → duration: fade 20s lalu pause | endOfSong: pause segera
      • cancel()       → batalkan timer + (bila ada) fade, restore volume
  → EventEmitter "sleepTimer" → EventChannel "musicplayer/media3_sleepTimer"
  → SleepTimerService.remaining / isActive  +  AudioPlaybackState.sleepTimer*
```

Timer sepenuhnya native (Handler di proses service), bukan Dart — benar untuk kasus app
di-background. Snapshot (`getPlaybackSnapshot`) ikut membawa `sleepTimerActive` +
`sleepTimerRemainingMs` untuk sinkronisasi reconnect (`TransportCommands.kt:481-483`,
`service.dart:818-819, 865-866`).

---

## Findings

### 🔴 F1 — End-of-song timer tidak mematikan musik di batas lagu ketika Crossfade aktif (dengan repeat-all: tidak pernah mati)

**Verdict: CONFIRMED BUG** — execution path nyata di produksi menghasilkan perilaku
salah: "stop setelah lagu ini" menjadi "putar seluruh queue", atau (repeat-all) "putar selamanya".

**Execution path**

```
user pilih "End of song"  (presets.dart _startPreset → SleepTimerService.startEndOfSong)
→ setSleepTimerEndOfSong → TransportCommands.kt:127-129 → SleepTimerManager.startEndOfSong (71-83)
→ lagu A mendekati akhir, crossfade aktif
→ TransportState position ticker (200ms) → CrossfadeController.maybeCrossfadeOut (TransportState.kt:74, CrossfadeController.kt:112)
→ beginCrossfade (CrossfadeController.kt:181-299):
     • standby (B) diset sebagai activePlayer SEBELUM standby.play()  (CrossfadeController.kt:244-247, 258-262)
     • queue player lama (A) dipangkas menjadi [A] saja + repeat OFF    (CrossfadeController.kt:275-299)
→ A mencapai STATE_ENDED
     • onPlaybackStateChanged (Media3PlaybackService.kt:1421-1439):
       `if (!isActiveEvent()) return` (1422) — activePlayer sudah B → event A di-drop.
       Check end-of-song (1433-1439) tidak pernah dievaluasi.
→ B tidak pernah menghasilkan onMediaItemTransition dengan reason AUTO:
     • transisi awal B saat prepare/play adalah PLAYLIST_CHANGED (bukan AUTO) → check (1481-1489) tidak jalan;
     • A tidak pernah "auto-advance" karena timeline-nya sudah dipangkas jadi [A].
→ lagu berikutnya (B, C, D, …) terus berjalan:
     • repeat OFF  → end-of-song baru terpicu di STATE_ENDED lagu TERAKHIR queue
                    (last track tidak masuk crossfade karena maybeCrossfadeOut early-return, CrossfadeController.kt:118-119)
     • repeat ALL  → lagu terakhir wrap → crossfade lagi → **timer TIDAK PERNAH terpicu**
```

**Counter-evidence (yang membuat kasus ini valid tapi bersyarat)**

- Crossfade OFF (default `crossfadeDuration = 0.0`, `audio_effects_service/service.dart:105, 188`):
  A→B transisi AUTO terjadi pada active player → `onMediaItemTransition` (1481-1489) → `triggerStop` benar.
- Queue 1 lagu / lagu terakhir + repeat off: STATE_ENDED active + `!crossfadeInProgress` → benar.
- Jadi bug butuh: **crossfade ON + queue > 1** (atau repeat-all).

**Impact**

User tidur sambil mendengar "sampai lagu ini selesai", musik tetap menyala melewati seluruh
queue; dengan repeat-all, musik tidak pernah berhenti. Fitur diam-diam tidak bekerja.

**Fix arah (belum diterapkan)**

1. Di `beginCrossfade`, jika `sleepTimerManager.sleepEndOfSong && sleepTimerActive`, jangan
   mulai crossfade — langsung `triggerStop()` (pause di batas, sesuai semantik).
2. Atau: di `onPlaybackStateChanged` STATE_ENDED, ganti guard `!crossfadeInProgress` dengan
   guard "STATE_ENDED milik player yang sedang crossfade-out" sehingga old player ENDED
   tetap bisa memicu triggerStop.
3. Atau: jadikan promotion (setActivePlayer / onCrossfadeComplete) ikut mengecek end-of-song
   dan trigger di sana.

---

### 🟠 F2 — Fade-out 20 detik tidak terkoordinasi dengan penulis volume lain (crossfade / play-pause) → fade salah player + race volume

**Verdict: CONFIRMED WEAKNESS** — path nyata ada, window sempit, dampak terbatas.

**Bukti**

- `SleepTimerManager.startFadeOut` (SleepTimerManager.kt:144-180) menangkap `player` + `initialVol`
  sekali di awal, tetapi **setiap tick membaca ulang `getPlayer()`** (= `activePlayer` saat itu,
  Media3PlaybackService.kt:352-356) — bukan player yang ditangkap.
- Jika crossfade mempromosikan standby di tengah fade (20 detik), step berikutnya menulis
  volume ke **player baru**, dan di akhir `p?.pause(); p?.volume = fadeInitialVolume` diterapkan
  ke player baru pula.
- Penulisan volume sleep-fade **berlomba** dengan `runEqualPowerFade` yang menulis volume
  tiap 16ms (CrossfadeController.kt:428-436). PlayPauseFadeController memang punya guard
  `isCrossfadeActive()` (PlayPauseFadeController.kt:77-85, 130-137), tetapi **SleepTimerManager
  tidak punya guard serupa** — ini penulis volume ketiga yang tidak diketahui keduanya.
- `handlePlay` (TransportCommands.kt:502-533) tidak membatalkan sleep-fade: user menekan play
  di tengah fade → `fadeInOnPlay` naik dari 0, sleep-fade terus menurunkan → beberapa detik
  kemudian fade selesai → **player di-pause lagi + volume di-restore** — aksi play user dibatalkan.
- Perubahan volume user selama fade dibuang (restore ke `fadeInitialVolume` yang di-capture,
  bukan ke volume terbaru) — kontras dengan PlayPauseFadeController yang membaca `getTargetVolume()`
  setiap tick.
- Fade tidak bisa dibatalkan dari UI selama 20 detik: `triggerStop` langsung
  `sleepTimerActive=false` (90-117) → sheet tidak menampilkan kartu aktif / tombol cancel.
  Satu-satunya jalan: start timer baru, atau skip (skipNext/Prev → `sleepTimerManager.cancel()`
  dengan guard `hadActiveFade`, SleepTimerManager.kt:119-129).

**Counter-evidence**

- Window 20 detik sempit; state akhir (pause + volume restore) umumnya sesuai keinginan user.
- Skip membatalkan fade dengan benar (restore volume pre-fade).
- Fade memakai `fadeInitialVolume` yang benar (bukan hardcoded 1.0) — perbaikan K11 sudah benar.

**Reachability produksi**

1. Timer duration habis ≤20s sebelum lagu berakhir + crossfade ON → promosi standby mid-fade.
2. Bit-perfect toggle mid-fade (pergantian player aktif).

---

### 🟠 F3 — State Dart bisa stale saat service mati dengan timer ter-armed; `release()` tidak emit

**Verdict: CONFIRMED WEAKNESS** (device-dependent; self-healing pada interaksi berikutnya).

**Bukti**

- `SleepTimerManager.release()` (SleepTimerManager.kt:206-211) hanya `cancelFadeOut()` +
  `cancelInternal()` — **tidak emit** `sleepTimer` `{active:false}`.
- `Media3PlaybackService.onDestroy` (Media3PlaybackService.kt:951) memanggil `release()` tanpa
  event penutup. EventChannel mati bersama service.
- Sisi Dart: `SleepTimerService.isActive` / `remaining` membeku (tidak ada event lagi).
  `syncFromNative()` saat service mati → `getPlaybackSnapshot` → `not_ready` (retry habis) →
  null → early-return (service.dart:762-780) → tidak ada koreksi.
- Sembuh sendiri saat sesi baru dimulai: `setQueue` → native `cancel()` (TransportCommands.kt:169)
  → emit `active:false` → UI tersinkron.

**Counter-evidence**

- Jalur STOP notifikasi sudah benar: `ACTION_STOP` memanggil `sleepTimerManager.cancel()`
  (Media3PlaybackService.kt:1052) → emit active:false sebelum teardown.
- Jalur `release` MethodChannel membatalkan timer dengan emit (`TransportCommands.kt:169/188`).
- Kegagalan terbatas pada kill sistem (swipe-away, OOM kill, Doze) — sulit dibuktikan tanpa device test.

---

### 🟡 F4 — `handleStop` (Dart `stop()`) tidak membatalkan sleep timer; `ACTION_STOP` notifikasi membatalkannya

**Verdict: CONFIRMED WEAKNESS** (inkonsistensi semantik, dampak rendah).

**Bukti**

- `handleStop` (TransportCommands.kt:560-588): pause/stop player, tidak ada `sleepTimerManager.cancel()`.
- `ACTION_STOP` (Media3PlaybackService.kt:1049-1061): `sleepTimerManager.cancel()` eksplisit.
- Akibat: `stop()` Dart (transient pause-and-idle) membiarkan timer ter-armed; ketika habis,
  fade/pause dijalankan pada player yang sudah stop (harmless), tetapi jika user play lagi
  sebelum timer habis, timer tetap menembak dan menghentikan sesi baru — mungkin mengejutkan
  karena stop biasanya berarti "sesi selesai".

**Counter-evidence**

- Semantik `stop()` memang "transient pause-and-idle" (media3_playback_bridge.dart:243-257) —
  mempertahankan timer bisa dianggap konsisten dengan "service tetap siap".
- Jalur lain (setQueue, setTrack, skip, setTrackNative, release, ACTION_STOP) sudah cancel.

---

### 🟡 F5 — State optimistik di Dart tanpa rollback (unawaited + error tak tertangani)

**Verdict: Confirmed weakness, severity rendah** — hampir tidak reachable setelah fix STOP
(turn sebelumnya), tapi polanya rapuh.

**Bukti**

- `SleepTimerService.startDuration` (sleep_timer_service.dart:47-53): `isActive=true`,
  `remaining=duration` diset **sebelum** `unawaited(PlaybackManager.setSleepTimer(...))`.
- `_invoke` (media3_playback_bridge.dart:221-233): retry `not_ready` 5× lalu **rethrow**;
  `unawaited` → unhandled async error (zone) + UI beku "aktif" tanpa native timer.
- Reachability: sheet hanya bisa dibuka dari player 3-dot (player_more_menu.dart:222) yang
  menuntut sesi aktif → service berjalan → `not_ready` jarang. Setelah STOP fix, currentSong
  di-clear → sheet tak terbuka. Tinggal kasus race cold-start yang sempit.

---

### 🟡 F6 — Dead code & doc drift

**Verdict: Confirmed (kosmetik), severity informasi.**

- Full-page `SleepTimerPage` (`sleep_timer_page/page.dart`, `body.dart` `_SleepTimerBody`)
  tidak dirujuk di mana pun — hanya bottom sheet `showSleepTimerSheet` yang dipakai.
- `_SleepTimerSheetBody` (sleep_timer_page.dart:86-88) berkomentar "preset taps also dismiss
  the sheet" tetapi memanggil `_PresetList(dismissOnSelect: false)` — sheet tetap terbuka
  dan menampilkan snackbar. Komentar tidak sinkron dengan kode.

---

## Verified strengths

- Timer berbasis Handler di proses service — tetap jalan saat app di-background, tidak
  bergantung pada Activity.
- `cancelInternal()`/`release()` menghapus semua runnable (timer, tick, fade) — tidak ada
  kebocoran Handler.
- K11 fix: fade me-restore `fadeInitialVolume` hasil capture (volume user), bukan 1.0 hardcoded.
- `cancel()` saat fade berjalan membatalkan fade + restore volume (guard `hadActiveFade`).
- `startDuration`/`startEndOfSong` membatalkan fade yang sedang berjalan dulu.
- Guard double-fire di `triggerStop` (`if (!sleepTimerActive) return`).
- SKIP-01: rapid-skip throttle drop sebelum side-effect cancel timer (TransportCommands.kt:598-605).
- Manual skip membatalkan end-of-song saja; duration-mode bertahan melewati ganti lagu (intended).
- End-of-song langsung pause (tanpa fade yang bocor ke lagu berikutnya) — benar.
- Metode sleep timer tidak menuntut player aktif (`TransportCommands.kt:121-133`) — bisa
  di-arm bahkan tanpa lagu.
- `emitAll` menyertakan `sleepTimer` (TransportState.kt:194-196) dan posisi ticker tidak —
  traffic EventChannel sehat (UW-01).
- Snapshot reconnect membawa state timer (TransportCommands.kt:481-483).

## Test gap

Belum ada unit/integration test untuk state machine sleep timer. Yang bernilai tinggi:

1. End-of-song + crossfade ON (queue > 1): harus pause di batas lagu pertama.
2. End-of-song + crossfade ON + repeat-all: harus tetap terpicu.
3. Fade duration-mode di-promote mid-fade oleh crossfade → fade harus tetap di player awal
   atau dibatalkan, bukan pindah ke player baru.
4. `play()` di tengah fade → fade harus dibatalkan, bukan re-pause.
5. Service destroy dengan timer armed → Dart harus menerima `active:false` (atau snapshot
   pull harus mengoreksi).

## Verification

- `dart analyze` pada semua file Dart sleep timer → **No issues found**.
- Kotlin: verifikasi statis (tidak ada Android SDK di environment ini; kompilasi Gradle tidak
  dapat dijalankan). Semua kutipan line number diambil langsung dari working tree.
- Tidak ada perubahan kode yang dilakukan selama audit ini.
