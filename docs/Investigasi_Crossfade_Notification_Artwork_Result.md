# Laporan Investigasi: Artwork Notification Terlambat Berganti Saat Crossfade

**Tanggal:** 2026-07-21  
**Status:** Root cause ditemukan. Belum ada patch.

---

## 1. Ringkasan Eksekutif

Artwork notifikasi terlambat berganti bukan karena source of truth yang salah — track baru sudah benar sejak awal crossfade. Masalahnya murni **latency pemuatan bitmap**: notifikasi selalu memuat artwork secara async, sementara Full Player bisa tampil instan karena pipeline-nya berbeda. Ada tiga faktor yang saling memperberat satu sama lain.

---

## 2. Timeline Lengkap Saat Crossfade (dari kode)

```
T = 0ms  beginCrossfade() masuk
│
├─ [270] setActivePlayer(standby)       → activePlayer = standby
├─ [276] setActiveQueueIndex(nextIndex) → activeQueueIndex = nextIndex
├─ [283] current.repeatMode = OFF       (isolasi old player)
├─ [293] switchSessionPlayer(standby)   → ActivePlayerProxy.switchTo(standby)
│        Listener yang terdaftar di proxy dimigrasikan ke standby.
│        (Catatan: listener dari attachPlayerListener() TIDAK lewat proxy —
│         langsung di-attach ke ExoPlayer instance masing-masing.)
│
├─ [304] standby.play()
│   │
│   ├── onIsPlayingChanged (standby)
│   │     isActiveEvent() = true (standby === activePlayer) ✓
│   │     getCurrentTrack() → activeQueueIndex = nextIndex → track BARU ✓
│   │     notificationManager.refresh()  ← CALL A
│   │     bitmapCache.get(cacheKey_new) = null (belum pernah dimuat)
│   │     → postNotification(bitmap=null)  ← notifikasi langsung tampil TANPA artwork
│   │     → refreshAsync(artUri_new, songId_new) → artworkLoadGeneration = G+1
│   │
│   └── onPlaybackStateChanged (standby)
│         isActiveEvent() = true ✓
│         notificationManager.refresh()  ← CALL B
│         bitmapCache.get(cacheKey_new) = null (masih miss)
│         → postNotification(bitmap=null)  ← notifikasi kembali tanpa artwork
│         → refreshAsync(...) → artworkLoadGeneration = G+2
│
├─ [311] emitAll()
│         EventEmitter.emit("currentTrack", currentTrackMap())
│         → Flutter menerima track BARU → Full Player update seketika ✓
│
└─ [312] refreshNotification() → notificationManager.refresh()  ← CALL C
          bitmapCache.get(cacheKey_new) = null (masih miss)
          → postNotification(bitmap=null)
          → refreshAsync(...) → artworkLoadGeneration = G+3

T = 0ms ... 100–600ms
artworkExecutor (single-thread) memproses 3 task secara berurutan:
  Task dari CALL A: loadBitmap() → 50–300ms → handler.post: generation G+1 ≠ G+3 → DIBUANG
  Task dari CALL B: loadBitmap() → 50–300ms → handler.post: generation G+2 ≠ G+3 → DIBUANG
  Task dari CALL C: loadBitmap() → 50–300ms → handler.post: generation G+3 == G+3 → DITERIMA
                                                → postNotification(bitmap=artworkBaru) ← ARTWORK MUNCUL

T = actualFadeMs (crossfade selesai, misal 3000ms)
  emitAll() + refreshNotification() dipanggil lagi.
  bitmapCache sudah ada artwork baru → postNotification() langsung sinkron ✓
```

**Kesimpulan timeline:** Track yang benar (new track) sudah digunakan sejak `setActiveQueueIndex(nextIndex)` di baris 276 — sebelum `standby.play()` dan `refreshNotification()`. Tidak ada window di mana notifikasi membaca track lama. Masalahnya bukan data salah, tapi **artwork harus dimuat ulang dari nol karena cache berbeda**.

---

## 3. Root Cause — Terbukti dari Kode

### RC-1 (UTAMA): `bitmapCache` notifikasi terpisah dari `ArtworkCacheManager` disk cache

**File:** `notification/PlaybackNotificationManager.kt`, baris 83

```kotlin
private val bitmapCache = android.util.LruCache<String, Bitmap>(10)
```

`bitmapCache` ini hanya diisi oleh `refreshAsync()` setelah `loadBitmap()` selesai. Ia **tidak terhubung** ke `ArtworkCacheManager`'s disk cache (`filesDir/artwork/{songId}.webp`).

Akibatnya, bahkan jika Full Player sudah pernah mengekstrak dan menyimpan artwork track ke WebP disk cache, notifikasi **tidak tahu** dan tetap memuatnya dari awal. Proses `refresh()` selalu memulai dari zero untuk setiap track baru.

`ArtworkCacheManager.getOrExtract()` memiliki fast path:
```kotlin
// Fast path — file already cached.
if (target.exists() && target.length() > 0L) {
    touch(target)
    return target.absolutePath  // <-- cepat, cuma File.exists()
}
```
Tapi fast path ini tidak dimanfaatkan secara sinkron oleh `refresh()`. Ia hanya dieksekusi di background thread, setelah `tryUri()` Stage 1 dijalankan dulu.

---

### RC-2 (PENGGANDA): 3 panggilan `refreshAsync()` beruntun di awal crossfade

**File:** `Media3PlaybackService.kt`, baris 1198–1203, 1177–1181; `CrossfadeController.kt`, baris 312

Di dalam `beginCrossfade()`, `standby.play()` memicu dua listener callbacks (`onIsPlayingChanged` dan `onPlaybackStateChanged`) yang keduanya memanggil `notificationManager.refresh()`. Ditambah satu panggilan eksplisit dari `refreshNotification()` di baris 312 CrossfadeController.

Total: **3 panggilan `refresh()` → 3 panggilan `refreshAsync()` dalam ~1ms**.

Setiap panggilan `refreshAsync()` menaikkan `artworkLoadGeneration`:

```kotlin
// PlaybackNotificationManager.kt baris 190
val generation = ++artworkLoadGeneration
```

Karena `artworkExecutor` adalah **single-threaded**, ketiga task mengantri secara berurutan. Task pertama dan kedua selesai tapi hasilnya **dibuang** oleh generation check:

```kotlin
if (generation != artworkLoadGeneration) return@post  // superseded
```

Artwork baru hanya muncul setelah task **ketiga** selesai — artinya, di worst case, total waktu tunggu = **3 × latency satu loadBitmap()** (bisa 150–900ms).

---

### RC-3 (DESIGN GAP): Tidak ada pre-waming artwork saat Phase 1 prewarm

**File:** `CrossfadeController.kt`, baris 120–124; `PreloadManager.kt`, baris 103–146

Phase 1 (`PREWARM_LEAD_MS = 1500ms` sebelum fade) mempersiapkan **audio pipeline** standby player. Tapi tidak ada yang mempersiapkan **artwork notifikasi** untuk track berikutnya.

```kotlin
// CrossfadeController.kt baris 120-123
if (!prewarmTriggered && remaining <= (crossMs + PREWARM_LEAD_MS)) {
    prewarmTriggered = true
    preloadManager.prewarmStandby()  // ← hanya audio, tidak ada artwork
    log("Pre-warm triggered @ remaining=${remaining}ms")
}
```

Selama jendela 1500ms ini, `artworkExecutor` menganggur. Jika artwork di-prewarm di sini, saat `beginCrossfade()` tiba `bitmapCache` sudah terisi dan `refresh()` akan memposting notifikasi dengan artwork instan.

---

### RC-4 (PENDUKUNG): `tryUri()` Stage 1 selalu jalan dulu sebelum fast path disk cache

**File:** `PlaybackNotificationManager.kt`, baris 292–315

```kotlin
private fun loadBitmap(artUri: String?, songId: Int): Bitmap? {
    // Stage 1: ContentResolver (bisa lambat 50–200ms di MIUI 12)
    val fromUri = tryUri(artUri)
    if (fromUri != null) return fromUri

    // Stage 2: ArtworkCacheManager (fast path jika file sudah ada)
    if (artworkCacheManager != null && songId > 0) {
        val path = artworkCacheManager.getOrExtract(songId)
        ...
    }
    return null
}
```

Untuk lagu dengan `albumId > 0`, `tryUri()` selalu mencoba dua kali buka `ContentResolver.openInputStream()` (pass 1: bounds, pass 2: decode). Di MIUI 12 / Android 11, ContentResolver bisa lambat 50–200ms per request. Stage 2 (disk cache) yang lebih cepat tidak pernah dicapai jika Stage 1 berhasil — tapi Stage 1 sendiri tetap membawa latency.

---

## 4. File dan Fungsi yang Terlibat

| File | Fungsi | Peran dalam Bug |
|------|--------|-----------------|
| `CrossfadeController.kt` | `beginCrossfade()` L270–312 | Promotion standby, trigger 3 refresh() |
| `CrossfadeController.kt` | `maybeCrossfadeOut()` L102–131 | Tidak pre-warm artwork saat Phase 1 |
| `PlaybackNotificationManager.kt` | `refresh()` L148–171 | Cache miss → async load → blank sementara |
| `PlaybackNotificationManager.kt` | `refreshAsync()` L181–204 | 3 task queue pada single thread |
| `PlaybackNotificationManager.kt` | `loadBitmap()` L292–316 | Latency tryUri() Stage 1 + disk Stage 2 |
| `Media3PlaybackService.kt` | `onIsPlayingChanged` L1198 | Memicu refresh() saat standby.play() |
| `Media3PlaybackService.kt` | `onPlaybackStateChanged` L1177 | Memicu refresh() saat standby.play() |
| `ArtworkCacheManager.kt` | `getOrExtract()` L91 | Fast disk path tersedia tapi tidak dipakai dari main thread |
| `TransportState.kt` | `currentTrackMap()` L234 | Memberi track baru yang benar — bukan penyebab bug |
| `TrackMapper.kt` | `currentTrackMap()` L21 | Pakai `activeQueueIndex` saat crossfade — sudah benar |

---

## 5. Mengapa Full Player Sudah Sinkron tapi Notification Belum

| | Full Player | Notification |
|-|-------------|--------------|
| **Dipicu oleh** | `emitAll()` → `EventEmitter.emit("currentTrack")` → Flutter stream | `notificationManager.refresh()` |
| **Sumber artwork** | `artworkCacheManager.getOrExtract(songId)` — disk cache shared | `bitmapCache` (private LruCache) + `artworkCacheManager` sebagai fallback async |
| **Timing update** | Sinkron di T=0 saat `emitAll()` dipanggil (line 311) | Async, selesai T+150ms hingga T+900ms |
| **Cache state** | Disk WebP sudah ada dari sesi sebelumnya → `File.exists()` instant | `bitmapCache` kosong untuk track baru → load ulang |
| **Redundansi** | Satu emit per crossfade start | 3 refresh() beruntun, 3 async tasks, hanya 1 yang dipakai |
| **Pre-warming** | N/A (stream event instan) | Tidak ada |

**Intinya:** Full Player memanfaatkan `artworkCacheManager` disk cache yang sudah diisi pada sesi/play sebelumnya — update `currentTrack` terjadi di baris 311 sebelum refresh notifikasi pun dipanggil. Notifikasi punya cache sendiri yang selalu kosong untuk track baru dan tidak punya mekanisme pre-loading.

---

## 6. Patch Minimal yang Diperlukan

Solusi terdiri dari **dua perubahan kecil** yang tidak memengaruhi latency audio maupun logika crossfade:

---

### Patch A — Deduplikasi `refreshAsync()`: tambahkan guard di `refreshAsync()`

**File:** `PlaybackNotificationManager.kt`

Masalah RC-2 (3 redundant async tasks) bisa diatasi dengan guard sederhana di dalam `refreshAsync()`: jika task untuk `cacheKey` yang sama sudah dalam antrian (track tidak berubah antar panggilan), lewati enqueue.

```kotlin
// Tambahan field di class:
private var pendingAsyncCacheKey: String? = null

private fun refreshAsync(
    artUri: String? = ...,
    songId: Int = ...,
    track: Map<String, Any?>? = ...,
    isPlaying: Boolean = ...,
) {
    val cacheKey = artUri ?: if (songId > 0) "song:$songId" else null
    if (cacheKey == null) return

    // NEW: skip enqueue jika cacheKey sama dengan yang sudah pending
    // (CALL A, B, C dalam ~1ms untuk track yang sama — hanya CALL C yang perlu)
    if (cacheKey == pendingAsyncCacheKey) return

    pendingAsyncCacheKey = cacheKey
    val generation = ++artworkLoadGeneration
    artworkExecutor.execute {
        val bmp = loadBitmap(artUri, songId)
        handler.post {
            pendingAsyncCacheKey = null  // <-- reset
            if (generation != artworkLoadGeneration) return@post
            ...
        }
    }
}
```

Efek: hanya 1 `loadBitmap()` call yang jalan per track, bukan 3. Latency berkurang hingga 3×.

---

### Patch B — Artwork prewarm: tambahkan `prewarmArtwork()` ke `PlaybackNotificationManager`

**File:** `PlaybackNotificationManager.kt` dan `CrossfadeController.kt`

Tambahkan method publik di `PlaybackNotificationManager`:

```kotlin
/**
 * Pre-loads artwork for [nextSongId]/[nextAlbumId] into bitmapCache
 * during Phase 1 prewarm, so refresh() at Phase 2 (crossfade start)
 * finds a cache hit and posts synchronously.
 */
fun prewarmArtwork(nextSongId: Int, nextAlbumId: Long) {
    val artUri = if (nextAlbumId > 0)
        "content://media/external/audio/albumart/$nextAlbumId" else null
    val cacheKey = artUri ?: if (nextSongId > 0) "song:$nextSongId" else null
    if (cacheKey == null) return
    // Already cached — nothing to do
    if (bitmapCache.get(cacheKey) != null || isInNoArtworkCache(cacheKey)) return

    // Load silently — don't post a notification, just warm the cache
    val generation = ++artworkLoadGeneration
    artworkExecutor.execute {
        val bmp = loadBitmap(artUri, nextSongId)
        handler.post {
            // Only store in cache, never post notification
            if (generation != artworkLoadGeneration) return@post
            if (bmp != null) bitmapCache.put(cacheKey, bmp)
            else markNoArtwork(cacheKey)
        }
    }
}
```

Di `CrossfadeController.kt`, tambahkan lambda baru `prewarmNotificationArtwork: (songId: Int, albumId: Long) -> Unit` dan panggil saat Phase 1:

```kotlin
// CrossfadeController.kt, di maybeCrossfadeOut() Phase 1 block:
if (!prewarmTriggered && remaining <= (crossMs + PREWARM_LEAD_MS)) {
    prewarmTriggered = true
    preloadManager.prewarmStandby()

    // NEW: pre-load notification artwork untuk next track
    val nextTrack = getQueue().getOrNull(preloadManager.preloadedQueueIndex)
    if (nextTrack != null) {
        val songId  = (nextTrack["id"] as? Number)?.toInt() ?: 0
        val albumId = (nextTrack["albumId"] as? Number)?.toLong() ?: 0L
        prewarmNotificationArtwork(songId, albumId)
    }
}
```

Di `Media3PlaybackService.kt`, wire lambda-nya ke `PlaybackNotificationManager`:

```kotlin
// Di CrossfadeController construction (sekitar baris 383):
prewarmNotificationArtwork = { songId, albumId ->
    notificationManager.prewarmArtwork(songId, albumId)
},
```

Efek: artwork tersedia di `bitmapCache` selambatnya saat `beginCrossfade()` dipanggil. `refresh()` menemukan cache hit → notifikasi diposting sinkron dengan artwork baru seketika, tanpa blank window.

---

## 7. Dampak Performa dan Risiko

- **Patch A** (dedup guard): zero overhead. Hanya tambah 1 string comparison per `refreshAsync()` call. Tidak ada perubahan timing audio.
- **Patch B** (prewarm): `loadBitmap()` yang dulunya terjadi di T=0 sekarang dimulai di T= −1500ms. Tidak ada pekerjaan ekstra — hanya dipindah waktu ke jendela prewarm yang sudah ada. `artworkExecutor` sudah ada dan biasanya idle saat prewarm.
- **Tidak ada dampak ke crossfade audio** — kedua patch beroperasi sepenuhnya di `artworkExecutor` background thread dan `handler.post`, tidak menyentuh ExoPlayer, volume, atau timing fade.
- **Tidak ada latency baru** yang diperkenalkan ke notifikasi — sebaliknya latency berkurang.
- **Worst case jika prewarm gagal** (track pertama kali, album art belum ada): fallback ke behavior saat ini (async load saat crossfade). User experience tidak lebih buruk dari kondisi sekarang.

---

## 8. Kandidat Logging Sementara (opsional, untuk verifikasi di device)

Tambahkan di `PlaybackNotificationManager.refresh()` untuk melihat kapan artwork tertinggal:

```kotlin
NativeLogger.emit("debug", "Notification",
    "refresh: track=${track?.get("id")} cacheKey=$cacheKey hasCached=$hasCached")
```

Tambahkan di `refreshAsync()` result handler:

```kotlin
NativeLogger.emit("debug", "Notification",
    "artwork loaded: cacheKey=$cacheKey bmp=${bmp != null} gen=$generation")
```

Ini akan memperlihatkan berapa ms antara "refresh: hasCached=false" dan "artwork loaded" di logcat.
