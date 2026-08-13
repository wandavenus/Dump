# Kotlin Code Audit — 2026-08-13

## Scope

Audit read-only menyeluruh terhadap **seluruh kode Kotlin produksi** di
`android/app/src/main/kotlin/dev/wndavenz/music/` (~17.000 baris, 39 file) +
spot-check test. Tidak ada kode yang diubah dalam audit ini.

File yang diaudit (semua dibaca penuh kecuali ditandai):
- Playback core: `Media3PlaybackService` (2.025), `TransportCommands` (765),
  `QueueManager` (285), `QueueSync` (163), `TransportState` (240),
  `ActivePlayerProxy` (269), `ServiceShutdownCoordinator` (127)
- Crossfade: `CrossfadeController` (465), `PreloadManager` (152),
  `CrossfadeTimelineLogger` (125)
- Audio effects: `AudioEffectsManager` (346), `NativeDspAudioProcessor` (171),
  `SignalsmithStretchAudioProcessor` (418), `StereoWideningAudioProcessor` (101),
  `StereoWidthManager` (79), `StretchManager` (142), `StretchAwareAudioProcessorChain` (102)
- Focus/offload: `AudioFocusManager` (206), `AudioOffloadManager` (218)
- Artwork: `PlaybackNotificationManager` (456), `FallbackBitmapLoader` (355),
  `SessionArtworkProvider` (327), `ArtworkCacheManager` (456), `BitmapUtils` (80)
- ReplayGain: `ReplayGainBridge` (393), `ReplayGainService` (271),
  `ReplayGainNative` (197), `ReplayGainModels` (145), `MediaStoreWriteGate` (328),
  `PcmDecoder` (156)
- Metadata: `MetadataCacheDb` (343), `MetadataPrescanner` (164), `TagBuilder` (163),
  `ExoMetadataReader` (141)
- Overlay/UI: `MainActivity` (1.465), `NowPlayingOverlayActivity` (339),
  `NativePaletteBridge` (928 — spot-check region concurrency), `NativePaletteModels` (62),
  `ColorScience` (68)
- Util/misc: `TrackMapper` (50), `MediaItemFactory` (42), `EventEmitter` (143),
  `FfmpegCapabilityProbe` (139), `SleepTimerManager` (200), `PlayPauseFadeController` (207)

Keterbatasan: Android SDK tidak tersedia di environment ini — verifikasi statis,
bukan kompilasi. Setiap finding diberi verdict: **Confirmed bug** / **Confirmed
weakness** / **Runtime-only** / **False positive**.

## Ringkasan eksekutif

Kualitas keseluruhan tinggi: praktik defensif (try/catch di setiap jalur I/O),
pola yang konsisten (semua volume automation berbagi satu main Handler),
dan hardening historis yang nyata (ActivePlayerProxy state-surface penuh,
QueueSync coalescing, MediaStoreWriteGate queue dialog, ReplayGain
write→verify→rollback, locks process-wide artwork, lifecycle exactly-once palette).

Ditemukan **2 temuan yang saya nilai Confirmed bug (P2)** di jalur produksi,
keduanya di area crossfade/promotion player, plus ~11 weakness kecil (P3).
Tidak ada P1 (crash/data-corruption/critical) yang baru ditemukan di luar yang
sudah di-fix pada audit sebelumnya.

---

## Temuan

### K1 (P2) — Cancel crossfade mid-fade dari noisy/audio-focus tidak me-rebuild queue promoted player → navigasi terkunci ke 1 lagu

**File / class / line:**
- `Media3PlaybackService.kt` — `noisyReceiver.onReceive` (:198-207)
- `Media3PlaybackService.kt` — lambda `onFocusLoss` saat membangun `AudioFocusManager` (:332-340)
- `CrossfadeController.kt` — `cancel(resetVolume)` (:161-182)
- `TransportCommands.kt` — `restoreQueueAfterCrossfadeCancel` (:583-593) — **satu-satunya** mekanisme rebuild setelah cancel

**Execution path (Confirmed reachable):**
1. User mendengarkan dengan crossfade > 0. `beginCrossfade()`
   (`CrossfadeController.kt:372-460`) **mengisolasi** old player ke tepat 1 item
   (remove tail + prefix) dan mem-promote standby (1-item timeline) sebagai
   active player.
2. Headphone dicabut saat fade berlangsung → `noisyReceiver` (:198) memanggil
   `crossfadeController.cancel(resetVolume = true)` lalu `player?.pause()`.
   ATAU audio focus hilang (telepon masuk) → `onFocusLoss` (:332) memanggil
   `crossfadeController.cancel(resetVolume = true)`.
3. `cancel()` (:161) memberhentikan/membersihkan **old** player
   (`promotionOwner`), tapi **tidak** me-rebuild timeline active player (masih
   1 item) dan tidak memanggil `rebuildPlayerQueue()`.
4. Jalur `pause/skip/setShuffle/setCrossfadeDuration` di TransportCommands
   sengaja memanggil `restoreQueueAfterCrossfadeCancel` (:583) setelah cancel —
   tapi dua pemanggil di atas (**bukan** TransportCommands) tidak melakukannya.
5. User resume → `handlePlay` (STATE bukan ENDED) → `p.play()` — player tetap
   1 item. `handleSkipNext` (:645): `wasCrossfading=false` (sudah di-cancel),
   `p.hasNextMediaItem()=false`, `mediaItemCount>0` → `seekToDefaultPosition(0)`
   → **lagu yang sama diputar lagi**. Navigasi next/prev terlihat "mati"
   sampai ada mutasi queue (setQueue/setTrack) yang me-rebuild.

**Evidence:** `CrossfadeController.kt:161-182` (cancel tidak memanggil
rebuild); `Media3PlaybackService.kt:198-207` & :332-340 (dua call site tanpa
`restoreQueueAfterCrossfadeCancel`); `TransportCommands.kt:583-593` (guard
`wasCrossfading` — bernilai false saat skip berikutnya terjadi).

**Counter-evidence:** `onMediaItemTransition` (:1270) memanggil
`setActiveQueueIndex` tapi itu hanya assignment integer, bukan rebuild
(`QueueManager.kt`). `rebuildPlayerQueue()` hanya dipanggil dari
`onCrossfadeComplete` dan `restoreQueueAfterCrossfadeCancel` — tidak ada yang
menjalankannya setelah cancel dari jalur noisy/focus.

**Verdict:** **Confirmed bug** — jalur produksi nyata, kondisi "headphone
dicabut / fokus hilang tepat saat crossfade" pasti terjadi di pemakaian normal.
Dampak: navigasi macet ke satu lagu sampai user mengganti queue; tidak crash,
tidak korup data.

**Severity:** P2 (perilaku salah, reachable 100%, tanpa crash).

**Fix — DITERAPKAN (lihat bagian "Fix K1 + K2 diterapkan" di bawah):**
`cancel()` kini menerima lambda `rebuildPromotedQueue` (default no-op) dan
memanggilnya saat mid-fade cancel; service me-wire ke
`queueManager.rebuildPlayerQueue()`.

---

### K2 (P2) — Akumulasi `AudioOffloadListener` pada player hasil promotion (duplikat event + leak lambat)

**File / class / line:**
- `Media3PlaybackService.kt` — `createConfiguredPlayer()` `.apply { ... }` (:1230)
- `Media3PlaybackService.kt` — `onCrossfadeComplete` lambda (:463-469)
- `Media3PlaybackService.kt` — inisialisasi awal `activeOffloadListener` (:247)

**Execution path:**
1. `createConfiguredPlayer()` (:1230): setiap player (termasuk semua standby
   yang dibuat via `PreloadManager.createPlayer`) menambah listener **tak
   ter-track** `addAudioOffloadListener(makeOffloadListener())` saat
   `::offloadManager.isInitialized`.
2. Promosi crossfade → `onCrossfadeComplete` (:463): remove
   `activeOffloadListener` (yang lama, dari player sebelumnya) lalu add
   listener BARU ke player yang baru dipromosikan.
3. Player yang dipromosikan kini punya ≥2 listener: yang dari langkah 1
   (untracked) + yang dari langkah 2 (tracked). Player ini di-demote → jadi
   standby lagi (object yang sama, tidak di-release) → promosi berikutnya
   menambah 1 lagi. **Akumulasi tak terbatas** seiring jumlah crossfade.

**Impact:** setiap `onOffloadedPlayback()` dipanggil N× per event → N event
`offloadState` duplikat ke Flutter + N baris log; memori listener bertambah
per crossfade. Bukan crash, tapi duplikasi event yang nyata dan growth tak
terikat.

**Counter-evidence:** `onDestroy` me-release player, jadi leak hanya selama
sesi service hidup. `removeAudioOffloadListener` hanya menghapus yang tracked
(:464).

**Verdict:** **Confirmed bug** (akumulasi nyata, bukan teori) — duplikasi
event/state dan growth linier per crossfade.

**Severity:** P2.

**Fix — DITERAPKAN (lihat bagian "Fix K1 + K2 diterapkan" di bawah):**
untracked add dihapus dari `createConfiguredPlayer`; helper
`attachOffloadListenerTo()` memelihara tepat SATU listener yang mengikuti
active player.

---

## Fix K1 + K2 — DITERAPKAN (2026-08-13)

### K1 — Queue restored setelah mid-fade cancel

**File:** `crossfade/CrossfadeController.kt`, `Media3PlaybackService.kt`

1. `CrossfadeController` menerima parameter baru `rebuildPromotedQueue:
   () -> Unit = {}` (default no-op → semua konstruksi lain tetap valid).
2. `cancel(resetVolume)` menangkap `wasMidFade = crossfadeInProgress` SEBELUM
   flag di-reset, dan di akhir memanggil `rebuildPromotedQueue()` hanya saat
   mid-fade. Promoted player yang punya timeline 1 item langsung diperluas
   ke queue penuh → next/prev tidak lagi terkunci ke satu lagu setelah
   headphone dicabut / audio focus hilang saat fade.
3. Service me-wire lambda ke `queueManager.rebuildPlayerQueue()`. Fungsi ini
   idempotent (skip saat `mediaItemCount == queue.size`), jadi jalur yang
   sudah restore eksplisit (TransportCommands pause/stop/skip, setQueue,
   shutdown, bit-perfect) menjadi no-op ganda yang aman.
4. `activeQueueIndex` sudah benar saat cancel: `beginCrossfade` meng-set-nya
   ke `nextIndex` sebelum fade (DP-1), jadi tidak perlu set ulang.

### K2 — Satu `AudioOffloadListener` global yang mengikuti active player

**File:** `Media3PlaybackService.kt`

1. **Untracked add dihapus** dari `createConfiguredPlayer()` — sumber utama
   akumulasi (tiap standby lama menyisakan 1 listener di player yang sama).
2. **Helper baru `attachOffloadListenerTo(player)`**: remove listener tracked
   dari primary, secondary, DAN bitPerfect (slot mana pun tempat ia menempel),
   lalu attach listener baru ke target. `makeOffloadListener()` murni observer
   `onOffloadedPlayback(Boolean)` — listener identity hanya soal bookkeeping,
   recreate aman.
3. **Call site:** `onCreate` (player awal) dan `onCrossfadeComplete` (player
   hasil promosi) — total tepat 1 listener di seluruh service, mengikuti
   active player.
4. **Bit-perfect:** tidak perlu call eksplisit — `switchToBitPerfectPlayer`
   menyimpan player aktif lama ke `preBitPerfectPlayer` (yang masih memegang
   tracked listener), dan `switchFromBitPerfectPlayer` me-restore object
   IDENTIK itu sebagai active player. Listener ikut kembali secara otomatis.
5. **Efek:** tidak ada lagi duplikat event `offloadState` maupun growth
   listener per crossfade.

### Verifikasi (Kotlin tidak bisa dikompilasi di environment ini)

- `grep` pada kode aktual (bukan hanya dokumen):
  - `addAudioOffloadListener` (non-komentar) hanya muncul di
    `attachOffloadListenerTo` → `Media3PlaybackService.kt:800`;
    tidak ada untracked add di `createConfiguredPlayer` (komentar K2 di
    :1262-1268 menandai penghapusan).
  - `removeAudioOffloadListener` hanya di :794-796 (satu helper).
  - Tidak ada sisa `val newOffloadListener`.
  - `rebuildPromotedQueue`: definisi sekali di `CrossfadeController.kt:63`
    (default `{}`), dipanggil sekali di :201 (guard `wasMidFade`), di-wire
    sekali di `Media3PlaybackService.kt:427`
    (`= { queueManager.rebuildPlayerQueue() }`).
- Semua 10 call site `cancel()` ditelusuri: noisy/focus kini me-rebuild via
  lambda; TransportCommands (pause/stop/skip/setShuffle/setCrossfadeDuration)
  jadi double-rebuild aman karena `rebuildPlayerQueue()` skip saat
  `mediaItemCount == queue.size`; shutdown/handlePlayUri/bit-perfect aman
  (queue kosong / try-catch / langsung diganti `setQueue`).
- Thread-safety: noisyReceiver (`onReceive`) dan `OnAudioFocusChangeListener`
  keduanya di-deliver di main thread → `rebuildPlayerQueue()` (API main-thread
  ExoPlayer) aman.
- Test baru (K1): `CrossfadeControllerTest` C06/C07/C08 menutup test gap #1 —
  mid-fade cancel memanggil `rebuildPromotedQueue` tepat sekali, non-mid-fade
  tidak memanggil sama sekali, dan kombinasi resetVolume tetap jalan.
  Test lama tidak tersentuh (semua pakai named arg; default lambda no-op).
- K1 membutuhkan konfirmasi akustik di device (cabut earphone saat fade),
  gap logikanya sudah tertutup dari kode.

---

### K3 (P3) — `QueueSync.save()` early-return pada queue kosong → prefs menyimpan queue basi yang di-restore saat system-restart

**File:** `QueueSync.kt:58` — `if (queue.isEmpty()) return`

Sesi yang berakhir dengan queue kosong tidak pernah di-persist, sehingga
`media3_queue_prefs` menyimpan snapshot non-kosong terakhir selamanya. Dengan
Plan A, restore hanya terjadi saat `intent == null` (system restart service) —
jadi setelah system membunuh proses, queue basi bisa muncul kembali padahal
user sudah mengosongkan queue-nya.

**Verdict:** **Confirmed weakness** (jalur nyata, dampak jarang & tergantung
fitur "kosongkan queue" di sisi Dart yang belum saya verifikasi eksistensinya).
**Severity:** P3.

---

### K4 (P3) — `EventEmitter.sinks` / `ServiceReadyGate.sink` tanpa sinkronisasi

**File:** `EventEmitter.kt:16-31`, `ServiceReadyGate.kt`

`HashMap` `sinks` diakses dari `emit()` dan `handler()` tanpa lock. Hari ini
semua pemanggil `EventEmitter.emit()` berjalan di main thread (TransportState,
listener Player, SleepTimerManager) dan `NativeLogger` sudah mem-posting ke
main — jadi kontrak aman **saat ini**. Tapi tidak ada enforcer: sekali ada
caller baru yang emit dari background thread (mis. native callback), ini jadi
`ConcurrentModificationException` / race.

**Verdict:** **Confirmed weakness** (kontrak implisit, tidak dilanggar hari ini).
**Severity:** P3 (hygiene). Fix opsional: `ConcurrentHashMap` + volatile.

---

### K5 (P3) — `deleteSong` di Android 10 (API 29) gagal diam-diam untuk file milik app lain

**File:** `MainActivity.kt:933-944`

minSdk = 29. Di API 29, `RecoverableSecurityException` ditangkap dan mengembalikan
`false` — tidak ada dialog konfirmasi (jalur `createDeleteRequest` hanya ada di
API 30+). User menekan hapus → tidak terjadi apa-apa, tanpa prompt dan tanpa
pesan. Di API 30+ jalurnya benar (dialog).

**Verdict:** **Confirmed weakness** (gap perilaku khusus API 29).
**Severity:** P3.

---

### K6 (P3) — `MainActivity.onDestroy` membiarkan MethodChannel result menggantung

**File:** `MainActivity.kt` — `onDestroy` (:1460-1464) + `postToFlutter` guard

`shutdownNow()` menolak task antrean → `onRejected` → `postToFlutter` no-op
karena `shuttingDown=true` → `result.success/error` tidak pernah dipanggil →
Future Dart menggantung selamanya untuk request yang masih antre/in-flight saat
Activity di-destroy. Jarang (Activity di-destroy biasanya bersamaan dengan
engine mati), tapi nyata.

**Verdict:** **Confirmed weakness.** **Severity:** P3.

---

### K7 (P3) — Retry `attachEffects` yang tertunda bisa menempel ke audio session mati

**File:** `AudioEffectsManager.kt` — `attachEffects` retry (:150-210)

Retry `postDelayed` tidak dibatalkan saat session berubah. Retry stale membangun
`Equalizer(0, oldSessionId)` ke session yang sudah tidak aktif lalu men-set
`lastAttachedSessionId = oldSessionId` — sesaat setelah itu, attach session baru
tetap jalan (id berbeda), jadi tidak ada poison permanen; hanya kerja sia-sia +
efek ter-attach ke session mati (exception tertelan, log warn).

**Verdict:** **Confirmed weakness.** **Severity:** P3.

---

### K8 (P3) — `MetadataCacheDb` bisa menyimpan dua baris untuk satu path

**File:** `MetadataCacheDb.kt` — `put()` (PK = songId) vs `putByPath()` (PK = FNV pathId)

Path yang sama bisa punya 2 baris (satu keyed songId, satu keyed pathId).
`getByPath` bisa mengembalikan baris pathId yang lebih tua; `updateLyrics` /
`invalidateByPath` hanya menyentuh baris yang cocok dengan path. Konsistensi
data jaga oleh mtime, jadi dampak praktis kecil, tapi modelnya ambigu.

**Verdict:** **Confirmed weakness.** **Severity:** P3.

---

### K9 (P3) — File `.tmp` artwork tidak pernah dibersihkan

**File:** `ArtworkCacheManager.kt` — `uniqueTempFile`, `saveRaw`/`saveAsWebP` finally, `cacheDir` lazy init, `cleanupIfNeeded` (filter `.webp`)

Writer gagal → `.tmp` tersisa. `cacheDir` sengaja tidak menghapus tmp (komentar
anti-race antar instance), dan LRU cleanup hanya memfilter ekstensi `.webp` —
jadi tmp menumpuk tanpa batas (tapi hanya pada kegagalan yang jarang).

**Verdict:** **Confirmed weakness.** **Severity:** P3.

---

### K10 (P3) — Identitas cache artwork hanya songId, tanpa fingerprint file

**File:** `ArtworkCacheManager.kt` — `getOrExtract`/`isUsableCacheFile`

Jika MediaStore me-reuse `_ID` untuk file berbeda (mis. setelah rescan/delete),
cache `{id}.webp` yang lama dianggap valid (bounds decode OK). `delete(songId)`
(A2) memitigasi saat app tahu lagu dihapus, tapi reuse-ID tanpa penghapusan
eksplisit tetap menampilkan artwork basi. Ini juga residual dari temuan lama
"mtime+size identity" — sisi **cache** tetap mtime-free (sisi **write**
ReplayGain sudah pakai size+mtime via `matchesIdentity`, lihat Verified
strengths).

**Verdict:** **Confirmed weakness** (limitasi desain, bukan bug baru).
**Severity:** P3.

---

### K11 (P3) — Sleep-timer fade mengembalikan volume ke 1.0f hardcoded

**File:** `SleepTimerManager.kt` — `startFadeOut` (:160-185) & `cancelFadeOut`

Setelah fade selesai (atau cancel), `player.volume = 1.0f` tanpa menghormati
volume user (mis. 0.3). Tidak terdengar salah permanen — `handlePlay` berikutnya
memanggil `fadeInOnPlay` yang menarik `getTargetVolume()` (= `volumeBeforeDuck`)
— tapi kondisi "paused" membawa volume 1.0 di state player, dan cancel di
tengah fade langsung lompat ke 1.0.

**Verdict:** **Confirmed weakness.** **Severity:** P3.

---

### K12 (P3) — `setupAudioEffectsChannel` hardcode `bassBoostSupported=true`

**File:** `MainActivity.kt` — `setupAudioEffectsChannel`, branch `"attachEffects"`

Selalu mengembalikan `bassBoostSupported=true` terlepas dari dukungan device
nyata (flag sebenarnya ada di `AudioEffectsManager.effectSupportMap()` via
`getEffectSupport`). Konsumen Dart bisa menampilkan kontrol bass yang tidak
berfungsi di device tanpa dukungan.

**Verdict:** **Confirmed weakness** (kebohongan kecil ke UI).
**Severity:** P3.

---

### K13 (P3) — Window `isPreviewMode` suppression sampai MethodChannel call pertama

**File:** `Media3PlaybackService.kt` — `onStartCommand` (:740-750) + `handle()` (:948-956)

Preview terakhir meninggalkan `isPreviewMode=true`; notifikasi tetap
suppressed sampai Flutter memanggil method channel apa pun yang lewat
`handle()`. Dalam praktik Flutter selalu memanggil channel saat start, jadi
jendela ini sempit; desain K3 sengaja menerimanya.

**Verdict:** **Confirmed weakness** (kosmetik, jarang terlihat).
**Severity:** P3.

---

## Verified strengths

- **Plan A:** restore queue hanya saat `intent == null` (system restart) —
  launch user-initiated selalu fresh. Konsisten dengan fix B di sisi Dart.
- **ActivePlayerProxy** (CE-05): seluruh state surface di-delegasikan ke
  `_current` (`getCurrentTimeline`, `getCurrentPeriodIndex`, `getMediaItemAt`,
  dll.) — konsistensi `createPositionInfo()` terjaga lintas promosi.
- **QueueSync:** executor tunggal daemon + coalescing `AtomicReference` —
  burst save = 1 I/O write; snapshot di-capture di main thread.
- **ReplayGain write:** fd-ownership disiplin (`detachFd`, TagLib yang
  menutup), protocol write→close→reopen→verify→rollback dengan `regionBackup`
  byte-exact, `STALE_SCAN` guard (canonical path + size+mtime), F3 identity
  snapshot sebelum scan, `invalidateByPath` setelah write. Temuan audit RG lama
  (cache invalidation after remove, mtime+size identity, fsync) **terkonfirmasi
  sudah ditangani** di jalur write.
- **MediaStoreWriteGate:** queue serial dialog (fix orphan callback), batch
  satu dialog via `createWriteRequest` (API 30+), fallback legacy batch API 29,
  verifikasi open-for-write nyata sebelum `granted=true`.
- **ArtworkCacheManager:** lock process-wide (`processGlobalLock` +
  `processSongLocks` + `processInFlightSongIds`), temp file unik per PID+thread,
  LRU throttle 15s, `isUsableCacheFile` memvalidasi decodable bounds.
- **NativePaletteBridge:** lifecycle lock + `disposed` flag, exactly-once
  completion via `completed.compareAndSet`, callback watchdog, OOM handling,
  coalescing per-song, queue-rejection safe.
- **Volume automation:** SleepTimer, PlayPauseFade, dan Crossfade semuanya
  berjalan di satu main Handler dengan guard `isCrossfadeActive` — tidak ada
  dua penulis volume pada player yang sama secara konkuren.
- **NativeDspAudioProcessor:** `streamSlot` per-instance mengisolasi state
  runtime per-stream native (fix data race lama).
- **StretchAwareAudioProcessorChain:** koreksi posisi media vs playout untuk
  speed ≠ 1.0 (fix drift + READY↔BUFFERING oscillation).
- **MetadataPrescanner:** generation counter monotonic (K1 fix) — tidak ada
  dua scan paralel, cancel yang aman.
- **PcmDecoder:** reuse ShortArray (zero alloc steady-state), validasi
  sampleRate/channels sebelum feed, release codec/extractor di finally.
- **SessionArtworkProvider:** in-flight registry per key + callbacks selalu
  dipanggil tepat sekali; `close()` menolak kerja baru setelah teardown.
- **FallbackBitmapLoader / notification:** semua callback memvalidasi
  generation + current-track sebelum post — stale results di-drop.

## Test gap (Kotlin)

1. ~~Tidak ada unit test untuk `TransportCommands`/`CrossfadeController.cancel`~~
   **DITUTUP**: `CrossfadeControllerTest` C06/C07/C08 (mid-fade cancel →
   `rebuildPromotedQueue` tepat sekali; non-mid-fade → tidak dipanggil;
   kombinasi resetVolume).
2. Tidak ada test yang memverifikasi jumlah `AudioOffloadListener` per player
   (K2) — mis. setelah 3 crossfade, tepat 1 listener. Memerlukan ExoPlayer
   mock yang mencatat add/remove listener (bisa ditambah sebagai unit test
   `attachOffloadListenerTo` bila perlu).
3. `ReplayGainBridgeTest` tidak mencakup `writeReplayGainBatch` / rollback
   verification-failed path.
4. `MediaStoreWriteGate` tidak punya test untuk queue drain + orphan
   prevention (hanya bisa di-Robolectric).

## Metodologi

- Semua file dibaca penuh (kecuali `NativePaletteBridge` — spot-check region
  concurrency karena sudah diaudit intensif sebelumnya).
- Setiap finding ditelusuri call graph dari entry point (MethodChannel,
  listener, receiver) sampai implementasi, termasuk semua call site — bukan
  hanya definisi pertama yang ditemukan.
- Verdict dibedakan tegas: bug (jalur eksekusi nyata → perilaku salah) vs
  weakness (limitasi nyata tanpa incorrect behavior terbukti) vs hygiene.
- Tidak ada severity yang dinaikkan hanya karena "secara teori bisa".
