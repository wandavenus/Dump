# Queue & Playback State Consistency Audit

**Tanggal:** 19 Juli 2026  
**Scope:** Queue desynchronization — Next/Previous tidak bekerja, UI menampilkan lagu berbeda, crossfade + shuffle + repeat  
**Metode:** Full code trace (QueueManager, CrossfadeController, PreloadManager, TransportCommands, TransportState, Media3PlaybackService, ActivePlayerProxy, TrackMapper)

---

## 1. Architecture Diagram

```
[Dart UI / AudioService]
        │
        │  MethodChannel (skipNext / skipPrevious / setQueue / setTrack / …)
        ▼
[TransportCommands.dispatch()]  ← SINGLE ENTRY POINT untuk semua perintah
        │
        ├─→ crossfadeController.cancel()          (membatalkan fade aktif)
        ├─→ preloadManager.clearStandbyQueue()     (menghentikan standby)
        ├─→ queueManager.*                         (mutasi queue in-memory)
        ├─→ p.seekTo* / p.setMediaItems()          (mutasi ExoPlayer)
        │
        ▼
[ExoPlayer (activePlayer)]  ← ENGINE
        │
        │  Player.Listener callbacks (main thread)
        ▼
[Media3PlaybackService.attachPlayerListener()]
        │
        │  isActiveEvent() guard → hanya event dari activePlayer yang diproses
        ├─→ onMediaItemTransition → queueManager.setActiveQueueIndex(p.currentIndex)
        ├─→ onIsPlayingChanged   → transportState.emitAll()
        ├─→ onPlaybackStateChanged → transportState.emitAll()
        │
        ▼
[TransportState.emitAll()]  ← SINGLE EMISSION PATH
        │
        │  EventChannel sinks (main thread)
        ▼
[Media3PlaybackBridge streams → AudioService → UI widgets]
```

### Sources of truth

| State | Authoritative owner | Backed up by |
|---|---|---|
| Queue list | `QueueManager.queue` | ExoPlayer internal playlist (in sync kecuali saat crossfade) |
| Current index | `QueueManager.activeQueueIndex` | ExoPlayer `currentMediaItemIndex` (sync via `onMediaItemTransition`) |
| Shuffle order | ExoPlayer internal (per-player) | `p.shuffleModeEnabled` flag di QueueSync |
| Repeat mode | ExoPlayer `repeatMode` | QueueSync |
| Playback state | ExoPlayer | EventChannel stream ke Dart |
| UI track info | Pure consumer dari `currentTrack` EventChannel | — |

---

## 2. Trace Lengkap per Flow

### 2A. User menekan Next

```
UI → AudioService.skipNext()
  → Media3PlaybackBridge.skipNext()  [MethodChannel: "skipNext"]
  → TransportCommands.handleSkipNext(p)
      1. sleepTimerManager.cancel()
      2. wasCrossfading = crossfadeController.crossfadeInProgress
         promotedIndex  = preloadManager.preloadedQueueIndex
      3. crossfadeController.cancel(resetVolume=true)
         → menghentikan fade runnable + mematikan old player (promotionOwner)
      4. preloadManager.clearStandbyQueue()
      5. [jika wasCrossfading && p.mediaItemCount < queue.size]
         → queueManager.setActiveQueueIndex(promotedIndex)
         → queueManager.rebuildPlayerQueue()  [full queue di-inject ke player]
      6a. [STATE_ENDED] → p.seekToDefaultPosition(nextIndex) + prepare() + play()
      6b. [normal]     → p.seekToNextMediaItem()  ← ExoPlayer handles shuffle/repeat
      7. preloadManager.preloadNextTrack(force=true)
      → onMediaItemTransition fires → queueManager.setActiveQueueIndex(p.currentIndex)
      → transportState.emitAll() → currentTrack EventChannel → UI
```

### 2B. User menekan Previous

```
UI → AudioService.skipPrevious()
  → TransportCommands.handleSkipPrevious(p)
      1. sleepTimerManager.cancel()
      2. wasCrossfading / promotedIndex (snapshot sebelum cancel)
      3. crossfadeController.cancel(resetVolume=true)
      4. preloadManager.clearStandbyQueue()
      5. [recovery block — sama persis dengan Next]
      6a. [STATE_ENDED] → p.seekToDefaultPosition(prevIndex) + prepare() + play()
      6b. [normal]     → p.seekToPreviousMediaItem()
          ⚠️  ExoPlayer threshold: jika currentPosition > maxSeekToPreviousPosition (3000ms)
              → restart current track, BUKAN ke track sebelumnya
      → onMediaItemTransition (jika item berubah) → queueManager.setActiveQueueIndex()
      → emitAll() → UI
```

### 2C. Lagu berakhir otomatis (auto-advance)

```
ExoPlayer auto-advance (ExoPlayer internal, bukan via TransportCommands)
  → onMediaItemTransition (reason=MEDIA_ITEM_TRANSITION_REASON_AUTO)
      guard: if (!crossfadeController.crossfadeInProgress && p.currentIndex >= 0)
        → queueManager.setActiveQueueIndex(p.currentMediaItemIndex)
        → crossfadeController.resetPromotionState()
        → preloadManager.preloadNextTrack(force=true)
      → queueSync.save()
      → transportState.emitAll()
      → notificationManager.refresh()
```

### 2D. Automatic Crossfade (lagu mendekati akhir)

```
Position ticker (200ms) → crossfadeController.maybeCrossfadeOut()
  Guard: crossfadeDurationSec > 0 && !promotionTriggered && !crossfadeInProgress
         && p.hasNextMediaItem() || repeatMode != OFF

Phase 1 — Pre-warm (remaining ≤ crossMs + 1500ms):
  preloadManager.prewarmStandby()
  → standby.volume=0 → standby.play() [pipeline warming, tidak terdengar]

Phase 2 — Crossfade (remaining ≤ crossMs + 250ms):
  beginCrossfade(actualFadeMs):
    1. crossfadeInProgress=true, promotionOwner=current  [LINE 217-219]
    2. current.removeMediaItems() prefix+suffix → isolasi old player ke 1 item
    3. standby.volume=0
    4. setActivePlayer(standby)   [LINE 271]  ← activePlayer sekarang = standby
    5. current.repeatMode=REPEAT_MODE_OFF
    6. activePlayerProxy.switchTo(standby)
    7. standby.prepare() jika diperlukan
    8. standby.play()              [LINE 299]  ← BISA trigger onIsPlayingChanged
    9. setActiveQueueIndex(nextIndex)  [LINE 309]  ← UPDATE INDEX ke track baru
   10. emitAll()                   [LINE 312]
   11. runEqualPowerFade() → 16ms Handler ticks, cos/sin volume fade

  runEqualPowerFade — step >= steps (selesai):
    1. setActiveQueueIndex(nextIndex)  [LINE 368 — redundan, sama value]
    2. newPlayer.volume = targetVol
    3. oldPlayer.pause() + stop() + clearMediaItems()
    4. onCrossfadeComplete():
       → queueManager.rebuildPlayerQueue()  [expand 1-item standby ke N items]
       → effectsManager.attachEffects(sessionId)
       → offloadManager.onCrossfadeComplete()
    5. emitAll()
    6. preloadManager.preloadNextTrack(force=true)
```

---

## 3. Possible Desynchronization Points

### DP-1 — Premature `currentTrack` emission sebelum index diupdate ⚠️

**Lokasi:** `CrossfadeController.kt`, `beginCrossfade()`, lines 271–312

**Mekanisme:**

```kotlin
// Line 271 — activePlayer sudah = standby
setActivePlayer(standby)

// Lines 292-303 — standby.prepare() jika IDLE/BUFFERING
if (standby.playbackState != Player.STATE_READY) standby.prepare()

// Line 299 — standby.play()
standby.play()
//  ↑ jika standby BELUM pre-warmed (playWhenReady=false sebelumnya),
//    maka isPlaying berubah false→true:
//    onIsPlayingChanged → isActiveEvent()=true → transportState.emitAll()
//    → currentTrackMap() membaca queueManager.activeQueueIndex = MASIH index LAMA

// Line 309 — baru diupdate setelah play()
setActiveQueueIndex(nextIndex)
```

**Kondisi trigger:** Prewarm tidak berhasil (standby masih IDLE atau BUFFERING saat
`beginCrossfade()` dipanggil), sehingga `standby.play()` mengubah `playWhenReady` dari
false→true dan memicu `onIsPlayingChanged`. Prewarm gagal bisa terjadi ketika:
- Track sangat pendek sehingga jendela prewarm (1500ms) tidak tercapai
- Latency I/O tinggi saat prewarm (disk read lambat)
- Buffer underrun saat prewarm

**Efek:** UI menerima `currentTrack` = Lagu A sementara audio sudah mulai Lagu B.
Selisih waktu biasanya hanya beberapa ms (antara `standby.play()` dan `setActiveQueueIndex`)
sebelum `emitAll()` di line 312 mengoreksinya. Tapi jika Flutter's stream listener batches
atau ada frame drop, UI bisa "stuck" di Lagu A untuk 1 frame atau lebih.

**Matches symptom:** ✅ "Audio continues playing but the UI shows a different song"

---

### DP-2 — Shuffle order di-randomize ulang setelah rebuildPlayerQueue ⚠️

**Lokasi:** `QueueManager.kt` `rebuildPlayerQueue()` + `PreloadManager.kt` line 71

**Mekanisme:**

Crossfade preload membaca `current.nextMediaItemIndex` — ini adalah index shuffled-next
dari ExoPlayer **A** (player lama dengan shuffle order asli).

```kotlin
// PreloadManager.kt line 71
val nextIndex = current.nextMediaItemIndex
// nextIndex = posisi shuffled-next menurut Player A
```

Setelah crossfade selesai dan `rebuildPlayerQueue()` dijalankan:
- Player B (standby yang dipromosikan) mulanya punya 1 item (Lagu B di index 0)
- `rebuildPlayerQueue()` menambahkan N-1 item lainnya via `addMediaItems()`
- ExoPlayer B **men-generate shuffle order baru** untuk N item tersebut secara independen
- Shuffle order B ≠ shuffle order A yang lama

**Efek:** Setelah crossfade selesai, `p.nextMediaItemIndex` pada player aktif baru
menghasilkan lagu yang berbeda dari yang "seharusnya" berdasarkan urutan shuffle A.
Track berikutnya (dan crossfade preload berikutnya) mengikuti urutan shuffle B yang baru
dibuat — berbeda dari yang diharapkan user.

**Matches symptom:** ✅ Lagu yang diputar tidak sesuai prediksi user setelah beberapa kali
crossfade dengan shuffle aktif

**Probability:** RARE (hanya saat shuffle=ON + crossfade aktif + user tidak skip manual)

---

### DP-3 — Previous button threshold + crossfade → apparent no-op ⚠️

**Lokasi:** `TransportCommands.kt`, `handleSkipPrevious()`, line 559

**Mekanisme:**

ExoPlayer's `seekToPreviousMediaItem()` menggunakan `maxSeekToPreviousPosition` (default: 3000ms).
Behavior:
- `currentPosition ≤ 3000ms` → seek ke previous item (Lagu A)
- `currentPosition > 3000ms` → restart current item dari 0 (tidak berpindah lagu)

Saat crossfade dengan durasi panjang (misalnya 5-8 detik):
1. Crossfade mulai: Lagu B mulai dari 0ms
2. Fade berjalan 3+ detik
3. User menekan Previous saat Lagu B sudah berjalan >3s
4. `seekToPreviousMediaItem()` → ExoPlayer restart Lagu B dari 0
5. `onMediaItemTransition` TIDAK fired (tidak ada perubahan item)
6. UI tetap menampilkan Lagu B, audio restart dari awal Lagu B

**Bagi user:** terlihat seperti "Previous tidak bekerja" karena lagu sama tetap
diputar (hanya restart diam-diam dari detik 0).

**Matches symptom:** ✅ "User presses Previous but playback does not change"

**Probability:** POSSIBLE (crossfade panjang ≥4s + user menekan Previous di pertengahan fade)

---

### DP-4 — handleSkipNext: index wrap-to-0 saat `hasNextMediaItem()=false` tanpa repeat

**Lokasi:** `TransportCommands.kt`, `handleSkipNext()`, lines 614-628

**Mekanisme:**

```kotlin
// Non-ENDED path, !p.hasNextMediaItem()
} else if (p.mediaItemCount > 0) {
    queueManager.setActiveQueueIndex(0)
    p.seekToDefaultPosition(0)
    // "Player listener handles emission"
}
```

`seekToDefaultPosition(0)` dari index terakhir (N-1) ke index 0 → `onMediaItemTransition`
fires (item berubah) → `queueManager.setActiveQueueIndex(0)` diset lagi (redundan tapi benar)
→ `emitAll()`. Secara fungsional benar.

NAMUN: bila shuffle aktif, wrap ini ke index LINEAR 0, bukan shuffle-next. Bila user berekspektasi
bahwa Skip di ujung queue dengan shuffle tetap mengikuti urutan shuffle, ini adalah desync
kecil antara ekspektasi dan perilaku actual.

**Status:** FALSE POSITIVE secara teknis (code benar, ini intentional design), NEEDS MORE DATA
dari user expectation.

---

### DP-5 — onMediaItemTransition dari old player tidak sepenuhnya di-guard (THEORETICAL)

**Lokasi:** `Media3PlaybackService.kt`, `attachPlayerListener()`, lines 1197-1237

**Guard saat ini:**

```kotlin
// Guard 1: event dari old player selama active crossfade → ignored
if (p === crossfadeController.promotionOwner && crossfadeController.crossfadeInProgress) return

// Guard 2: event bukan dari activePlayer → ignored
if (!isActiveEvent()) return

// Guard 3: jangan update index saat crossfade in-progress
if (!crossfadeController.crossfadeInProgress && p.currentMediaItemIndex >= 0) {
    queueManager.setActiveQueueIndex(p.currentMediaItemIndex)
}
```

Ketiga guard ini saling melengkapi dan BENAR. Analisis shows tidak ada path yang melewatkan
ketiga guard sekaligus. **Status: FALSE POSITIVE** — guard sudah solid.

---

### DP-6 — Crossfade + Repeat ONE (NEEDS MORE DATA)

**Lokasi:** `CrossfadeController.kt`, `maybeCrossfadeOut()`, line 108

```kotlin
if (!p.hasNextMediaItem() && p.repeatMode == Player.REPEAT_MODE_OFF) return
```

Untuk `REPEAT_MODE_ONE`: ExoPlayer's `hasNextMediaItem()` behavior dengan REPEAT_ONE
perlu verifikasi. Jika `hasNextMediaItem()` returns false saat REPEAT_ONE (karena tidak ada
"next different item"), maka condition menjadi:
`!false && mode != OFF` → **tidak return** → crossfade berjalan.

Ini berarti dengan Repeat ONE + Crossfade, lagu B yang di-preload adalah... lagu yang sama?
`preloadManager.preloadNextTrack()` membaca `current.nextMediaItemIndex` — dengan REPEAT_ONE
ini adalah current index → standby akan preload lagu yang sama. Crossfade dari A ke A.

**Probability:** POSSIBLE (Repeat ONE + Crossfade aktif secara bersamaan)
**Risk:** Bukan desync, tapi perilaku tidak intuitif (crossfade lagu dengan dirinya sendiri).

---

## 4. Stress Test Analysis

### Case A: Shuffle ON, Repeat OFF, Crossfade ON
- **DP-1** (POSSIBLE): premature emission jika prewarm gagal
- **DP-2** (RARE): shuffle order re-randomized setelah rebuildPlayerQueue

### Case B: Shuffle ON, Repeat ALL, Crossfade ON
- **DP-1** (POSSIBLE): sama seperti Case A
- **DP-2** (RARE): shuffle order issue lebih signifikan dengan Repeat ALL (queue terus loop)
- Tambahan: old player isolation di `beginCrossfade()` men-disable REPEAT_MODE_ALL pada old player
  (via `current.repeatMode = REPEAT_MODE_OFF` di line 278). Guard `isActiveEvent()` memastikan
  `onRepeatModeChanged` dari old player tidak ter-emit ke Flutter. ✅ Aman.

### Case C: Shuffle OFF, Repeat ONE, Crossfade ON
- **DP-6** (NEEDS MORE DATA): crossfade mungkin preload track yang sama

### Case D: Rapid Next → Next → Previous → Next (beberapa detik)
- Semua MethodChannel calls dieksekusi di **main thread** (Android main looper)
- Position ticker (Handler) juga di main thread
- → Tidak ada actual race condition antara rapid skips
- `cancel()` + `clearStandbyQueue()` di setiap skip membersihkan state dengan benar
- **Status: FALSE POSITIVE** — tidak ada desync dari rapid skipping

---

## 5. UI Synchronization Verification

### Mini Player + Full Player
- Source: `currentTrack` EventChannel → satu stream, satu source ✅
- Tidak bisa menampilkan lagu berbeda secara simultan (kecuali DP-1 transient window)

### Notification
- `notificationManager.refresh()` dipanggil setelah setiap `emitAll()` yang relevan
- Menggunakan `transportState.currentTrackMap()` → sama source dengan UI ✅
- Kecuali pada window kecil di DP-1 (premature play() sebelum setActiveQueueIndex)

### Queue Screen
- `queue` EventChannel hanya di-emit saat `emitQueue=true` (mutations, setQueue, subscribe)
- Queue list sendiri konsisten dengan `QueueManager.queue` ✅

### Apakah bisa menampilkan lagu berbeda secara simultan?
- **Secara teori:** YA, dalam window kecil DP-1 (beberapa ms hingga sebelum `emitAll()` di line 312)
- **Secara praktis:** Hanya jika prewarm gagal dan Dart stream listener memproses event sebelum emitAll() koreksi

---

## 6. Findings Summary

| ID | Status | Probability | File | Fungsi | Line | Deskripsi |
|---|---|---|---|---|---|---|
| **DP-1** | **VALID** | **POSSIBLE** | `CrossfadeController.kt` | `beginCrossfade()` | 271–312 | `standby.play()` bisa fire `emitAll()` sebelum `setActiveQueueIndex(nextIndex)` → UI brief shows wrong track |
| **DP-2** | **VALID** | **RARE** | `QueueManager.kt` + `PreloadManager.kt` | `rebuildPlayerQueue()`, `preloadNextTrack()` | 71, 176+ | Shuffle order direset setelah crossfade promotion — `nextMediaItemIndex` pada player baru tidak konsisten dengan ekspektasi user |
| **DP-3** | **VALID** | **POSSIBLE** | `TransportCommands.kt` | `handleSkipPrevious()` | 559 | `seekToPreviousMediaItem()` threshold 3s → dengan crossfade panjang, Previous restart current track bukan ke track sebelumnya |
| **DP-4** | **FALSE POSITIVE** | — | `TransportCommands.kt` | `handleSkipNext()` | 614–628 | wrap-to-0 saat no-next: fungsional benar, `onMediaItemTransition` handles emission |
| **DP-5** | **FALSE POSITIVE** | — | `Media3PlaybackService.kt` | `attachPlayerListener()` | 1197–1237 | Triple guard (`promotionOwner`, `isActiveEvent`, `crossfadeInProgress`) solid |
| **DP-6** | **NEEDS MORE DATA** | POSSIBLE | `CrossfadeController.kt` | `maybeCrossfadeOut()` | 108 | Repeat ONE + Crossfade: `hasNextMediaItem()` behavior dengan REPEAT_ONE perlu verifikasi |
| **DP-7** | **FALSE POSITIVE** | — | `TransportCommands.kt` | `handleSkipNext/Prev()` | 565–631 | Rapid skipping: semua di main thread, tidak ada actual race |

---

## 7. Fix Recommendations (tanpa implementasi)

### Untuk DP-1 (MOST CRITICAL)

**Masalah:** `setActiveQueueIndex(nextIndex)` dipanggil SETELAH `standby.play()`.

**Rekomendasi:** Pindahkan `setActiveQueueIndex(nextIndex)` ke SEBELUM `standby.play()`
(atau sebelum `standby.prepare()`), agar semua emitAll() yang mungkin ter-trigger oleh
prepare/play callbacks sudah membaca index yang benar.

```
// Urutan yang aman:
setActivePlayer(standby)        // update activePlayer
switchSessionPlayer(standby)    // update proxy
setActiveQueueIndex(nextIndex)  // UPDATE INDEX DULU  ← PINDAHKAN KE SINI
standby.prepare() jika perlu    // callbacks setelah ini sudah baca index baru
standby.play()                  // emitAll() dari onIsPlayingChanged sudah benar
emitAll()                       // tidak lagi "terlambat"
```

> ⚠️ Perlu verifikasi bahwa komentar "K-02: Do NOT call setActiveQueueIndex before fade starts"
> (line 224-229) masih relevan setelah perubahan ini — komentar tersebut membahas efek ke ExoPlayer,
> bukan ke `queueManager` yang hanya mengubah integer tanpa side effect ke ExoPlayer.

### Untuk DP-2 (Shuffle order reset)

**Masalah:** ExoPlayer men-generate shuffle order baru secara independen setelah `addMediaItems()`.

**Rekomendasi:** Setelah `rebuildPlayerQueue()`, snapshot `nextMediaItemIndex` dari player baru
dan bandingkan dengan `preloadedQueueIndex`. Jika berbeda, force-reload preload dengan index
yang sesuai (`preloadManager.preloadNextTrack(force=true)` sudah dipanggil, tapi ini tidak
memperbaiki shuffle order). Solusi yang lebih dalam: pertimbangkan untuk menonaktifkan shuffle
pada standby player sebelum promotion, lalu restore + `seekToWindowIndex` secara eksplisit
setelah `rebuildPlayerQueue()` agar shuffle order diterapkan dari posisi yang diketahui.

### Untuk DP-3 (Previous threshold)

**Masalah:** `seekToPreviousMediaItem()` menggunakan default threshold 3000ms ExoPlayer.

**Rekomendasi:** Di `handleSkipPrevious()`, sebelum memanggil `seekToPreviousMediaItem()`,
periksa `p.currentPosition` secara eksplisit:

```kotlin
if (p.currentPosition > p.maxSeekToPreviousPosition && p.hasPreviousMediaItem()) {
    // User bermaksud ke track sebelumnya, bukan restart — lakukan manual
    val prevIdx = p.previousMediaItemIndex
    if (prevIdx != C.INDEX_UNSET) p.seekToDefaultPosition(prevIdx)
} else {
    p.seekToPreviousMediaItem()
}
```

Atau: pertimbangkan untuk mengatur `maxSeekToPreviousPosition` ke nilai kecil (misalnya 0)
pada player, sehingga "Previous" selalu berarti "go to previous track" tanpa threshold.

### Untuk DP-6 (Repeat ONE + Crossfade)

**Rekomendasi:** Tambahkan explicit guard di `maybeCrossfadeOut()`:
```kotlin
if (p.repeatMode == Player.REPEAT_MODE_ONE) return  // crossfade tidak masuk akal untuk repeat-one
```

---

## 8. Constraints

- Media3 / DSP / ReplayGain / UI design: tidak diubah
- Dokumen ini adalah **diagnosis-only audit**
