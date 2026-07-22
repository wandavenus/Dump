# Laporan Lanjutan — Verifikasi Root Cause Artwork Notification

> Status: **Semua poin dalam checklist terbukti dari kode. Tidak ada asumsi.**
> Tidak ada perubahan kode dalam dokumen ini.

---

## 1. Event Timeline Lengkap

Timeline di bawah mencakup satu skenario paling umum: user mengetuk lagu, Flutter memanggil `setQueue` lalu `play`.

### Fase A — `setQueue` (Dart → Kotlin)

```
TransportCommands.dispatch("setQueue")
  ├─ crossfadeController.cancel()
  ├─ QueueManager.setQueue(items, index)
  │     └─ p.setMediaItems(
  │           items.map { MediaItemFactory.from(it) },   ← MediaItem dibuat di sini
  │           index, posMs
  │        )
  │        p.prepare()
  ├─ transportState.emitAll(emitQueue=true)
  └─ notificationManager.refresh()              ← [REFRESH #1]
```

**`refresh()` #1:**
```
artUri = getCurrentTrack()?.get("artworkUri")   ← "content://.../albumart/{albumId}"
                                                    atau null jika albumId=0
cached = artworkCache.get(artUri)               ← null (belum ada)
hasCached = false
postNotification(buildNotification(..., null))  ← notifikasi tanpa artwork
refreshAsync(artUri, track, isPlaying)          ← load async, generation=1
```

`refreshAsync()` langsung queue ke `artworkExecutor`:
```
artworkExecutor.execute {
    bmp = loadBitmap(artUri)                    ← ContentResolver pass-1 + pass-2
    handler.post {
        if (generation != artworkLoadGeneration) return@post
        if (bmp != null) artworkCache.put(artUri, bmp)
        else noArtworkUris.add(artUri)
        postNotification(buildNotification(..., bmp))   ← notifikasi dengan/tanpa artwork
    }
}
```

### Fase B — ExoPlayer listener events (dipicu oleh `p.prepare()`)

ExoPlayer memproses `setMediaItems + prepare` dan memanggil listener:

```
onPlaybackStateChanged(STATE_BUFFERING)
  └─ notificationManager.refresh()              ← [REFRESH #2]
     artUri sama → hasCached masih false → refreshAsync(), generation=2
     (artworkExecutor queue sekarang: task#1, task#2)
```

### Fase C — `play` (Dart → Kotlin)

```
TransportCommands.handlePlay(p)
  ├─ audioFocusManager.request()
  ├─ playPauseFadeController.fadeInOnPlay(p)
  ├─ p.play()
  ├─ ensureMediaForeground()                    ← [ENSURE FOREGROUND]
  │     isForeground=false → masuk ke startForeground path:
  │     track = getCurrentTrack()
  │     buildNotification(..., bitmap=null)
  │     startForegroundWith(notification)       ← startForeground() dipanggil di sini
  │     isForeground = true
  │     refreshAsync()                          ← tanpa argumen, baca getCurrentTrack() ulang
  │                                                generation=3
  │     (artworkExecutor queue: task#1, task#2, task#3)
  ├─ notificationManager.refresh()              ← [REFRESH #3, line 477]
  │     artUri sama → hasCached false → generation=4
  ├─ transportState.startPositionTicker()
  └─ transportState.emitAll()
     notificationManager.refresh()              ← [REFRESH #4, line 486]
     artUri sama → hasCached false → generation=5
```

### Fase D — ExoPlayer listener events (dipicu oleh `p.play()`)

```
onIsPlayingChanged(true)
  ├─ transportState.startPositionTicker()
  ├─ transportState.emitAll()
  └─ notificationManager.refresh()              ← [REFRESH #5]
     artUri sama → hasCached false → generation=6

onPlaybackStateChanged(STATE_READY)
  └─ notificationManager.refresh()              ← [REFRESH #6]
     artUri sama → hasCached false → generation=7

onMediaItemTransition(reason=TRANSITION_REASON_PLAYLIST_CHANGED)
  ├─ queueSync.save()
  ├─ transportState.emitAll()
  └─ notificationManager.refresh()              ← [REFRESH #7]
     artUri sama → hasCached false → generation=8
```

### Fase E — artworkExecutor menjalankan tasks

Semua 8 task antri di `artworkExecutor` (single thread). Setiap task memanggil `loadBitmap(artUri)` dua kali (bounds pass + decode pass) via `ContentResolver`.

**Skenario SUKSES (MediaStore sudah indeks albumId):**
```
Task #1: loadBitmap → Bitmap OK → handler.post { generation(1) != 8 → return@post }
Task #2: loadBitmap → Bitmap OK → handler.post { generation(2) != 8 → return@post }
...
Task #8: loadBitmap → Bitmap OK → handler.post { generation(8) == 8 → lanjut }
         artworkCache.put(artUri, bmp)
         postNotification(buildNotification(..., bmp))   ← artwork muncul di notifikasi
         notificationManager.notify(NOTIFICATION_ID, notification)
```

**Skenario GAGAL (MediaStore belum indeks):**
```
Task #1: loadBitmap → null → handler.post { generation(1) != 8 → return@post }
...
Task #8: loadBitmap → null → handler.post { generation(8) == 8 → lanjut }
         noArtworkUris.add(artUri)              ← ⚠ BLACKLIST PERMANEN
         postNotification(buildNotification(..., null))  ← artwork tetap kosong

Semua refresh() berikutnya:
  hasCached = (artUri in noArtworkUris) = true → tidak ada retry selamanya
```

---

## 2. Apakah MediaSession Diperbarui Setelah Artwork Tersedia?

**Jawaban: TIDAK. Tidak ada satupun pemanggilan `setMediaMetadata`, `replaceMediaItem`, atau metadata-update setelah artwork selesai dimuat.**

Bukti dari kode:

`refreshAsync()` (baris 172–182) setelah bitmap dimuat:
```kotlin
handler.post {
    if (generation != artworkLoadGeneration) return@post
    if (bmp != null) artworkCache.put(artUri, bmp) else noArtworkUris.add(artUri)
    val sess = getSession() ?: return@post
    // ← HANYA ini yang dilakukan setelah bitmap selesai:
    postNotification(buildNotification(sess, getCurrentTrack(), getIsPlaying(), bmp))
    // Tidak ada: session.player.replaceCurrentMediaItem()
    // Tidak ada: session.setCustomLayout()
    // Tidak ada: player.setMediaMetadata()
    // Tidak ada: player.replaceMediaItem()
}
```

`buildNotification()` (baris 213–252) menggunakan `MediaStyleNotificationHelper.MediaStyle(session)` — ini hanya **menghubungkan notification style ke MediaSession** agar tombol transport berfungsi. Ini TIDAK memperbarui `MediaMetadata` yang ada di dalam MediaSession.

**Konsekuensi yang diketahui:**
- **Notification (status bar):** diperbarui dengan bitmap setelah artwork dimuat — `notificationManager.notify()` di `postNotification()` memperbarui tampilan yang user lihat di status bar.
- **Lock screen / Bluetooth (via MediaSessionLegacyStub):** menggunakan `FallbackBitmapLoader`. `FallbackBitmapLoader.loadBitmap(uri)` dipanggil oleh Media3 saat MediaItem baru diset (waktu `p.setMediaItems()`), bukan saat notifikasi artwork selesai. `FallbackBitmapLoader` punya dua-pass: `tryUri()` (ContentResolver) → `tryEmbedded()` (MediaMetadataRetriever + MediaStore query). Ini lebih baik dari `PlaybackNotificationManager.loadBitmap()` karena punya embedded fallback.

**Kesimpulan untuk poin ini:** MediaSession MediaMetadata tidak diperbarui setelah artwork loading. Tapi ini **tidak menyebabkan bug notification** — karena `postNotification()` sudah cukup untuk memperbarui tampilan notifikasi. Bug notification artwork kosong disebabkan oleh `loadBitmap()` yang return null, bukan oleh kurangnya MediaSession update.

---

## 3. Apakah Notification Benar-Benar Di-refresh Setelah Bitmap Tersedia?

**Jawaban: YA, trigger ada dan benar — JIKA bitmap berhasil dimuat.**

Bukti dari kode `refreshAsync()` (baris 163–183):
```kotlin
artworkExecutor.execute {
    val bmp = loadBitmap(artUri)
    handler.post {
        if (generation != artworkLoadGeneration) return@post
        if (bmp != null) artworkCache.put(artUri, bmp) else noArtworkUris.add(artUri)
        val sess = getSession() ?: return@post
        try {
            postNotification(buildNotification(sess, getCurrentTrack(), getIsPlaying(), bmp))
            //               ^^^^^^^^^^^^^^^^^ ← trigger ada
        } catch (e: Exception) { ... }
    }
}
```

`postNotification()` (baris 185–195):
```kotlin
private fun postNotification(notification: Notification) {
    if (!isForeground) {
        startForegroundWith(notification)
    } else {
        notificationManager.notify(NOTIFICATION_ID, notification)
        //                  ^^^^^^ ← Android NotificationManager dipanggil
    }
}
```

**Tidak ada missing trigger.** Pipeline rebuild-dan-post setelah bitmap selesai adalah **benar dan lengkap**.

**Yang menjadi masalah adalah input ke trigger tersebut** — jika `loadBitmap()` return null, `bmp=null` diteruskan ke `buildNotification(..., null)`, dan `builder.setLargeIcon(it)` tidak pernah dipanggil (baris 232: `bitmap?.let { builder.setLargeIcon(it) }`). Notification diposting tanpa artwork.

---

## 4. Root Cause Final (Terbukti dari Kode)

Ada **dua root cause mandiri** yang saling memperkuat:

### RC-A: `loadBitmap()` hanya menggunakan ContentResolver — tidak ada embedded fallback

**File:** `PlaybackNotificationManager.kt`, baris 265–284

```kotlin
private fun loadBitmap(artUri: String?): Bitmap? {
    if (artUri.isNullOrBlank()) return null
    return try {
        val uri = Uri.parse(artUri)
        if (uri.toString().contains("/albumart/-") || uri.toString().endsWith("/0")) return null

        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        service.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, boundsOpts)        // Pass 1
        }

        val sample = computeSampleSize(...)
        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
        service.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, decodeOpts)        // Pass 2
        }
    } catch (_: Exception) { null }
}
```

Tidak ada fallback ke `MediaMetadataRetriever.embeddedPicture`. Jika `contentResolver.openInputStream()` gagal (MediaStore belum indeks album, albumId=0, file non-standar), fungsi langsung return null.

Bandingkan dengan `FallbackBitmapLoader.loadBitmap()` yang sudah ada di proyek ini:
```kotlin
val bmp = tryUri(uri) ?: tryEmbedded(uri)    // ← punya embedded fallback
```

`PlaybackNotificationManager` menggunakan pipeline yang lebih lemah daripada `FallbackBitmapLoader` yang sudah ada.

**Kasus yang pasti gagal:**
- `buildSongMapFromUri()` (file manager open): `albumId=0` → `artUri=null` → line 168: `if (artUri == null) return` — tidak pernah mencoba load apapun
- Lagu baru ditambahkan: MediaStore belum selesai scan → `openInputStream` throw `FileNotFoundException` → catch → return null
- File di direktori non-standar (Telegram, WhatsApp): MediaStore tidak scan direktori ini → URI tidak valid

### RC-B: `noArtworkUris` blacklist permanen mencegah retry dalam sesi

**File:** `PlaybackNotificationManager.kt`, baris 72–77 dan 174

```kotlin
// Saat kegagalan:
noArtworkUris.add(artUri)           // ditambahkan SELAMANYA

// Saat refresh() berikutnya:
val hasCached = artUri == null
    || artworkCache.get(artUri) != null
    || artUri in noArtworkUris      // ← TRUE → hasCached=true → tidak retry
```

Ini adalah **desain yang salah untuk kasus ini**. `noArtworkUris` ditujukan untuk optimisasi (menghindari ulang MediaStore query yang diketahui gagal), tapi ia memengaruhi kasus di mana kegagalan bersifat sementara (MediaStore scan belum selesai). Sekali gagal, tidak ada retry sampai app di-restart.

**Kasus yang paling sering terpicu:**
- Lagu pertama di sesi baru, MediaStore belum selesai scan saat lagu mulai
- 8 `refresh()` calls rapid-fire (lihat timeline di atas): hanya task #8 yang hasilnya dipakai. Jika task #8 gagal → blacklist. Padahal task #1 mungkin sudah berhasil, tapi hasilnya di-skip oleh generation check.

---

## 5. Evaluasi Patch Sebelumnya

### Patch A: Fallback ke ArtworkCacheManager

**Ini adalah root fix yang benar, bukan workaround.**

Alasannya:
- Menggunakan source yang sama dengan Full Player: `MediaMetadataRetriever.embeddedPicture` baca langsung dari file audio
- Tidak bergantung pada MediaStore album art indexing
- Memanfaatkan disk cache WebP yang sudah ada (`{filesDir}/artwork/{songId}.webp`) — jika Full Player sudah menampilkan lagu ini, file sudah ada di disk, load dari notifikasi tinggal `BitmapFactory.decodeFile()`

**Implementasi paling bersih:**

`songId` sudah tersedia tanpa perlu modifikasi apapun. `TrackMapper.currentTrackMap()` mengembalikan `songMap + mapOf(...)`. `songMap["id"]` adalah `songId` (MediaStore `_ID`):

```kotlin
// Di refreshAsync() dan loadBitmap():
val songId = (getCurrentTrack()?.get("id") as? Number)?.toInt() ?: 0

// Modifikasi loadBitmap() — tambah songId parameter:
private fun loadBitmap(artUri: String?, songId: Int): Bitmap? {
    // Existing: fast path via ContentResolver
    if (!artUri.isNullOrBlank()) {
        val uri = Uri.parse(artUri)
        if (!uri.toString().contains("/albumart/-") && !uri.toString().endsWith("/0")) {
            try {
                // Pass 1 + Pass 2 (existing code)
                val bmp = existingTwoPassDecode(uri)
                if (bmp != null) return bmp
            } catch (_: Exception) { }
        }
    }

    // NEW: fallback via disk cache atau ArtworkCacheManager
    if (songId > 0) {
        val webpFile = File(service.filesDir, "artwork/$songId.webp")
        if (webpFile.exists() && webpFile.length() > 0) {
            return try { BitmapFactory.decodeFile(webpFile.absolutePath) } catch (_: Exception) { null }
        }
        // Jika belum ada di disk, ekstrak sekarang (blocking di background thread)
        val artworkManager = ArtworkCacheManager(service)
        val path = artworkManager.getOrExtract(songId)
        if (path != null) {
            return try { BitmapFactory.decodeFile(path) } catch (_: Exception) { null }
        }
    }
    return null
}
```

`ArtworkCacheManager(service)` adalah constructor ringan — tidak ada state yang perlu dishare. Bisa di-lazy-init di `PlaybackNotificationManager`.

**Apakah ini menyembunyikan bug?**

Tidak. Ini memperbaiki penyebabnya (source bitmap yang salah), bukan hanya membypass efeknya. `PlaybackNotificationManager` tetap menggunakan pipeline yang terbukti benar (sama dengan Full Player).

---

### Patch B: `noArtworkUris`

**Ini adalah bug desain yang nyata. Fix-nya wajib.**

Blacklist permanen `noArtworkUris` adalah desain yang tepat untuk tujuan awalnya (mencegah retry berulang pada song yang memang tidak punya artwork). Tapi ia menjadi masalah karena:
1. Kegagalan `loadBitmap()` bisa sementara (MediaStore belum selesai scan)
2. Blacklist tidak dibersihkan antar track changes

**Solusi paling aman:**

Ganti semantik dari "blacklist permanen" menjadi "blacklist per-track". Clear entry saat track baru mulai, bukan saat app restart:

```kotlin
// Di refresh(), sebelum mengecek hasCached — clear URI track sebelumnya jika track berubah:
private var lastSeenArtUri: String? = null

fun refresh() {
    val artUri = track?.get("artworkUri") as? String
    // Jika track berganti, hapus blacklist entry lama sehingga track baru dapat retry
    if (artUri != lastSeenArtUri) {
        lastSeenArtUri?.let { noArtworkUris.remove(it) }
        lastSeenArtUri = artUri
    }
    // ... existing code
}
```

Dengan Patch A di tempatnya, `noArtworkUris` hanya terisi jika KEDUA path gagal (ContentResolver + ArtworkCacheManager/disk). Ini berarti lagu yang benar-benar tidak punya embedded art sama sekali — kasus yang sangat jarang dan blacklist memang benar di sana.

---

### Patch C: Tambah `songId` ke output `TrackMapper`

**Patch ini TIDAK diperlukan. Batalkan.**

`songId` sudah ada di `currentTrackMap()` tanpa modifikasi apapun.

Bukti dari `TrackMapper.kt` baris 40–44:
```kotlin
return songMap + mapOf(
    "index"          to index,
    "artworkUri"     to artUri,
    "nextTrackIndex" to nextTrackIndex,
)
```

`songMap` adalah `queue.getOrNull(index)` — yaitu item yang dikirim Flutter melalui `setQueue`. Flutter mengirim map lengkap termasuk field `"id"` (MediaStore `_ID` = songId). Field `"id"` ada di `songMap`, dan `songMap` ter-spread ke result map.

Di `PlaybackNotificationManager.loadBitmap()`:
```kotlin
val songId = (getCurrentTrack()?.get("id") as? Number)?.toInt() ?: 0
```

Sudah berfungsi tanpa modifikasi `TrackMapper`. Patch C tidak perlu dibuat.

---

### Patch D: Fix parameter default `refreshAsync()` di `ensureMediaForeground()`

**Patch ini NICE-TO-HAVE, prioritas rendah, risiko sangat kecil.**

Issue-nya:
```kotlin
private fun refreshAsync(
    artUri: String? = getCurrentTrack()?.get("artworkUri") as? String,  // evaluasi ke-1
    track: Map<String, Any?>? = getCurrentTrack(),                        // evaluasi ke-2
    ...
)
```

Dua evaluasi `getCurrentTrack()` ini terjadi secara sinkron di main thread Handler. Tidak ada yield di antara keduanya. Race condition teoritis sangat kecil dalam praktiknya.

Jika ingin diperbaiki:
```kotlin
fun ensureMediaForeground() {
    if (isForeground) return
    ensureChannel()
    val track = getCurrentTrack()     // capture sekali
    val artUri = track?.get("artworkUri") as? String
    val songId = (track?.get("id") as? Number)?.toInt() ?: 0
    val notification = buildNotification(getSession(), track, getIsPlaying(), bitmap = null)
    startForegroundWith(notification)
    refreshAsync(artUri, songId, track, getIsPlaying())
}
```

Ini juga tempat yang tepat untuk memasukkan `songId` ke panggilan `refreshAsync`.

---

## 6. Ringkasan: Patch Mana yang Wajib

| # | Patch | Status | Alasan |
|---|-------|--------|--------|
| A | Fallback ke disk cache + ArtworkCacheManager di `loadBitmap()` | **WAJIB** | Root fix nyata. Menyelaraskan notification dengan Full Player pipeline |
| B | Hapus `noArtworkUris` untuk track aktif saat track berganti | **WAJIB** | Mencegah kegagalan sementara menjadi kegagalan permanen |
| C | Tambah `"songId"` ke TrackMapper output | **BATALKAN** | `"id"` sudah ada di map, tidak perlu modifikasi TrackMapper |
| D | Fix double-evaluation `getCurrentTrack()` di `refreshAsync()` | Opsional | Risiko sangat kecil, bukan root cause |

---

## 7. Patch Mana yang Sebaiknya Dibatalkan

**Batalkan Patch C.** `TrackMapper.kt` tidak perlu diubah. `songId` sudah tersedia melalui `getCurrentTrack()?.get("id")`. Memodifikasi `TrackMapper` hanya menambah kompleksitas tanpa manfaat — nama `"id"` sudah cukup jelas dan konsisten dengan field yang sama di sisi Flutter (`LocalSong.id`).

**Patch D boleh diabaikan** untuk saat ini. Tidak ada bukti bahwa double-evaluation menyebabkan bug nyata di device target (Mi 9T, Android 11, main thread adalah single-thread looper).

---

## Lampiran: Inventory Semua Pemanggil `refresh()`

| Lokasi | Kondisi Trigger |
|--------|----------------|
| `TransportCommands.dispatch("setQueue")` L155 | Selalu saat queue diganti |
| `TransportCommands.handlePlay()` L477 | Setelah `p.play()` |
| `TransportCommands.handlePlay()` L486 | Setelah `transportState.emitAll()` |
| `TransportCommands.handleSkipPrevious()` L557 | STATE_ENDED path |
| `TransportCommands.handleSkipNext()` L613 | STATE_ENDED path |
| `CrossfadeController.refreshNotification` L445 | Setelah crossfade selesai |
| `onPlaybackStateChanged()` L1172 | Setiap state change |
| `onIsPlayingChanged()` L1194 | Play/pause toggle |
| `onMediaItemTransition()` L1236 | Track berganti |
| `switchToBitPerfectPlayer()` L1725 | Bit-Perfect mode on |
| `switchFromBitPerfectPlayer()` L1774 | Bit-Perfect mode off |

Seluruh pemanggil `refresh()` sudah diidentifikasi. Tidak ada pemanggil tersembunyi. Notification selalu di-refresh saat state berubah — masalahnya bukan pada frekuensi refresh, melainkan pada `loadBitmap()` yang return null saat MediaStore belum siap.
