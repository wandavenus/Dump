# Laporan Investigasi — Artwork Notification Kadang Kosong

> Status: **Root cause ditemukan. Belum ada perubahan kode.**
> Semua kesimpulan didukung bukti dari kode sumber.

---

## Ringkasan Eksekutif

Bug bukan berasal dari satu titik, melainkan **kombinasi lima faktor**:

| # | Faktor | Kelas |
|---|--------|-------|
| 1 | Sumber bitmap berbeda antara Full Player dan Notification | Arsitektur |
| 2 | `albumId=0` menghasilkan `artUri=null` → tidak ada artwork selamanya | Data |
| 3 | `noArtworkUris` mem-blacklist URI secara permanen dalam sesi | Race / Caching |
| 4 | Notifikasi pertama selalu diposting tanpa bitmap | Race Condition |
| 5 | `refreshAsync()` di `ensureMediaForeground()` bisa return lebih awal | Race Condition |

---

## 1. Peta Flow Artwork — Full Player vs Notification

### 1.1 Full Player (selalu benar)

```
LocalSong.id (songId, MediaStore _ID)
   │
   ▼
ArtworkRepository.getProviderSync(songId)   ← Dart, synchronous first-frame
   │
   ├─ Hit: _paths[songId] → FileImage("{filesDir}/artwork/{songId}.webp")
   │
   └─ Miss:
        ArtworkRepository.getProvider(songId)  ← async, waktu berikutnya
           │
           ├─ Layer 2: File("{filesDir}/artwork/{songId}.webp") exists?
           │      → FileImage → done
           │
           └─ Layer 3: MediaStoreService.getArtworkPath(songId)
                  │   (MethodChannel)
                  ▼
              ArtworkCacheManager.getOrExtract(songId)
                  │
                  ├─ Fast path: {cacheDir}/{songId}.webp exists → return path
                  │
                  └─ Slow path:
                       MediaMetadataRetriever.setDataSource(context, MediaStore URI)
                       .embeddedPicture           ← baca langsung dari file audio
                       → decodeScaledBitmap(raw)  ← max 1000×1000
                       → compress WebP 85%
                       → atomic rename ke {songId}.webp
                       → return path
```

**Kata kunci:** kunci cache = `songId`. Sumber = **embedded bytes dari file audio**. Tidak bergantung pada MediaStore mengindeks album art.

---

### 1.2 Notification (kadang gagal)

```
getCurrentTrack() → TrackMapper.currentTrackMap()
   │
   └─ albumId = songMap["albumId"]  ← dari queue map
      artUri  = if (albumId > 0)
                    "content://media/external/audio/albumart/$albumId"
                else null
      ──────────────────────────────────────
      ⚠ Jika albumId=0 → artUri=null → tidak ada artwork, selesai di sini.
      ──────────────────────────────────────

PlaybackNotificationManager.refresh()
   │
   ├─ cached = artworkCache.get(artUri)        ← LruCache<String, Bitmap>(10)
   ├─ hasCached = (artUri==null)
   │            || artworkCache.get(artUri)!=null
   │            || artUri in noArtworkUris      ← ⚠ blacklist permanen
   │
   ├─ postNotification(buildNotification(..., cached))  ← null jika belum ada
   │
   └─ if (!hasCached && artUri != null) → refreshAsync()
          │
          └─ artworkExecutor.execute {
                 bmp = loadBitmap(artUri)
                    │
                    └─ contentResolver.openInputStream(Uri.parse(artUri))
                          ← ⚠ gagal jika MediaStore belum mengindeks albumId
                          ← ⚠ gagal jika albumId aneh / tidak ada di tabel albums
                       BitmapFactory.decodeStream(stream)
                 handler.post {
                     if (bmp != null) artworkCache.put(artUri, bmp)
                     else noArtworkUris.add(artUri)   ← ⚠ blacklist selamanya
                 }
             }
```

---

## 2. Perbandingan Lengkap Full Player vs Notification

| Dimensi | Full Player | Notification |
|---------|-------------|--------------|
| **Kunci cache** | `songId` (MediaStore `_ID`) | `artUri` (string album art URI) |
| **Sumber bitmap** | `MediaMetadataRetriever.embeddedPicture` — baca langsung dari file audio | `ContentResolver.openInputStream(albumArtUri)` — baca dari database MediaStore |
| **Prasyarat** | File audio harus punya embedded art | MediaStore harus sudah mengindeks album art untuk `albumId` ini |
| **Cache disk** | `{filesDir}/artwork/{songId}.webp` — persisten, bertahan restart | Tidak ada — hanya RAM |
| **Cache memory** | `LinkedHashMap` 300 entri + `_diskCachedIds` set | `LruCache<String, Bitmap>(10)` — hanya 10 entri |
| **Failure mode** | Null hanya jika file tidak punya embedded art | Null jika MediaStore belum indeks, albumId=0, atau LRU evict → blacklist |
| **Recovery** | Tidak perlu — disk cache permanen | Tidak ada — `noArtworkUris` mencegah retry selamanya |
| **Thread** | Dart isolate + `Dispatchers.IO` (MethodChannel) | `artworkExecutor` (single daemon thread) |

---

## 3. Root Cause Detail

### RC-1: Sumber artwork berbeda (penyebab utama)

**File:** `TrackMapper.kt` baris 32–33, `PlaybackNotificationManager.kt` baris 265–284

Full Player menggunakan `MediaMetadataRetriever.embeddedPicture` yang membaca langsung dari byte audio file. Ini **selalu berhasil** selama file memiliki embedded art.

Notification menggunakan `content://media/external/audio/albumart/{albumId}` yang membaca dari **tabel album art di database MediaStore**. URI ini hanya valid jika:
- MediaStore sudah selesai scan file tersebut
- File berada di direktori yang di-scan MediaStore
- `albumId` valid dan ada di tabel `audio_albums`

Lagu yang baru ditambahkan, file dari Telegram/WhatsApp, atau file di direktori non-standar sering belum ter-indeks → `openInputStream()` throw `FileNotFoundException` → `loadBitmap()` return null.

```kotlin
// TrackMapper.kt:32-33 — artUri HANYA dari albumId, bukan songId
val artUri = if (albumId > 0)
    "content://media/external/audio/albumart/$albumId" else null
```

```kotlin
// PlaybackNotificationManager.kt:274 — hanya coba ContentResolver
service.contentResolver.openInputStream(uri)?.use {
    BitmapFactory.decodeStream(it, null, boundsOpts)
}
// Jika null → loadBitmap return null
```

Sedangkan `ArtworkCacheManager` yang dipakai Full Player:
```kotlin
// ArtworkCacheManager.kt:189-200
val uri = Uri.withAppendedPath(
    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId.toString()
)
val mmr = MediaMetadataRetriever()
mmr.setDataSource(context, uri)  // buka file audio, bukan album art URI
val bytes = mmr.embeddedPicture  // baca embedded bytes langsung
```

---

### RC-2: `albumId=0` → artUri=null → tidak pernah ada artwork

**File:** `TrackMapper.kt` baris 31–33, `MediaItemFactory.kt` baris 21–23

Jika `albumId=0` atau tidak ada di map lagu, `artUri=null`. Notification tidak pernah mencoba load apapun:

```kotlin
// PlaybackNotificationManager.kt:168
if (artUri == null) return  // ← langsung return, tidak ada fallback
```

Kondisi `albumId=0` terjadi pada:
- Lagu yang diputar via `handlePlayUri()` (file manager / external app) — lihat `Media3PlaybackService.kt:730`: `"albumId" to 0`
- Lagu yang tidak ter-indeks MediaStore sama sekali
- Lagu yang `buildSongMapFromUri()` tidak bisa ekstrak metadata album

---

### RC-3: `noArtworkUris` blacklist permanen — race condition yang membeku

**File:** `PlaybackNotificationManager.kt` baris 72–77, 174

```kotlin
// Jika loadBitmap() gagal (apapun sebabnya):
if (bmp != null) artworkCache.put(artUri, bmp)
else noArtworkUris.add(artUri)   // ← ditambahkan SELAMANYA dalam sesi ini
```

```kotlin
// Di refresh() berikutnya:
val hasCached = artUri == null
    || artworkCache.get(artUri) != null
    || artUri in noArtworkUris   // ← BENAR → hasCached=true → tidak retry
```

**Scenario bug:**
1. Lagu A diputar. MediaStore belum selesai scan → `loadBitmap()` gagal.
2. `noArtworkUris.add(artUri_A)` — ditandai "tidak ada artwork".
3. MediaStore selesai scan 5 detik kemudian — artwork A sudah terindeks.
4. Refresh notification berikutnya: `artUri_A in noArtworkUris` → `hasCached=true` → tidak ada retry.
5. Artwork tidak pernah muncul sampai app di-restart.

Ini adalah **false-negative permanent** dalam satu sesi.

---

### RC-4: Notifikasi pertama selalu diposting tanpa bitmap

**File:** `PlaybackNotificationManager.kt` baris 121–130

```kotlin
fun ensureMediaForeground() {
    // ...
    val notification = buildNotification(getSession(), track, getIsPlaying(), bitmap = null)  // ← bitmap=null
    startForegroundWith(notification)  // ← post tanpa artwork
    refreshAsync()                     // ← load async setelahnya
}
```

Ini adalah desain yang sengaja (supaya tidak melewatkan deadline 5 detik Android), tapi ini juga berarti notifikasi pertama **pasti kosong**. Jika `refreshAsync()` setelahnya gagal (RC-2 atau RC-3), artwork tidak pernah muncul.

---

### RC-5: `refreshAsync()` bisa return lebih awal karena artUri null saat dipanggil

**File:** `PlaybackNotificationManager.kt` baris 163–168

```kotlin
private fun refreshAsync(
    artUri: String? = getCurrentTrack()?.get("artworkUri") as? String,  // ← baca ulang track
    track: Map<String, Any?>? = getCurrentTrack(),                        // ← baca ulang lagi
    ...
) {
    if (artUri == null) return   // ← early return
```

`ensureMediaForeground()` memanggil `refreshAsync()` tanpa argumen → default parameter membaca `getCurrentTrack()` saat itu. Jika service baru start dan `currentTrackMap()` belum punya data valid (queue masih kosong saat restore), `artUri=null` → return → tidak ada load.

Selain itu, `getCurrentTrack()` dipanggil **dua kali** di parameter default, bukan dari nilai yang sudah di-capture — bisa race condition jika track berubah di antara dua panggilan.

---

## 4. File dan Fungsi yang Terlibat

| File | Fungsi / Baris | Peran dalam Bug |
|------|---------------|-----------------|
| `notification/PlaybackNotificationManager.kt` | `refresh()` L136 | Memutuskan apakah load artwork |
| `notification/PlaybackNotificationManager.kt` | `refreshAsync()` L163 | Load bitmap async — bisa return lebih awal |
| `notification/PlaybackNotificationManager.kt` | `loadBitmap()` L265 | Sumber bitmap hanya ContentResolver |
| `notification/PlaybackNotificationManager.kt` | `ensureMediaForeground()` L121 | Post bitmap=null, refreshAsync tanpa argumen |
| `notification/PlaybackNotificationManager.kt` | `noArtworkUris` L72 | Blacklist permanen — mencegah retry |
| `utils/TrackMapper.kt` | `currentTrackMap()` L21 | artUri hanya dari albumId, tidak ada songId |
| `utils/MediaItemFactory.kt` | `from()` L21–23 | artworkUri hanya dari albumId |
| `ArtworkCacheManager.kt` | `getOrExtract()` L91 | Sumber yang benar — tidak dipakai notifikasi |
| `Media3PlaybackService.kt` | `buildSongMapFromUri()` L730 | albumId=0 untuk file external |
| `FallbackBitmapLoader.kt` | `loadBitmap()` L98 | Hanya untuk Bluetooth/lock screen via MediaSessionLegacyStub |

---

## 5. Mengapa Full Player Selalu Benar, Notification Gagal

**Full Player:**
- Pakai `songId` → path langsung ke file audio → `MediaMetadataRetriever.embeddedPicture`
- Tidak bergantung MediaStore indexing
- Disk cache WebP persisten di `{filesDir}/artwork/` — tidak pernah hilang dalam sesi
- `ArtworkRepository` tidak punya blacklist permanen

**Notification:**
- Pakai `albumId` → URI MediaStore album art → `ContentResolver`
- Bergantung sepenuhnya pada MediaStore yang sudah mengindeks album art
- Cache hanya RAM (10 entri LRU) — di-evict setelah 10 album berbeda
- `noArtworkUris` mencegah retry setelah satu kegagalan

---

## 6. Kesimpulan: Penyebab Bug

Bug berasal dari **kombinasi**:

- **Arsitektur** (utama): Notification dan Full Player menggunakan **sumber bitmap yang berbeda**. Full Player menggunakan embedded audio bytes langsung; Notification bergantung pada indeks MediaStore yang mungkin belum siap.
- **Race condition**: Notifikasi pertama diposting tanpa artwork, dan `refreshAsync()` bisa gagal karena artUri null saat dipanggil.
- **Caching**: `noArtworkUris` blacklist yang permanen mencegah retry walau kondisi sudah berubah (MediaStore selesai scan).
- **Data**: `albumId=0` → artUri=null → tidak ada artwork sama sekali untuk lagu yang dibuka dari file manager.

---

## 7. Rencana Patch — Paling Aman, Tanpa Trade-Off

### Patch 1 (Wajib): Fallback ke disk cache `ArtworkCacheManager`

Ubah `loadBitmap()` di `PlaybackNotificationManager` agar setelah gagal via ContentResolver, fallback ke file WebP yang sudah diekstrak `ArtworkCacheManager`:

```kotlin
// Di refreshAsync() / loadBitmap(), terima juga songId:
private fun loadBitmap(artUri: String?, songId: Int): Bitmap? {
    // Fast path: coba album art URI (sudah terindeks MediaStore)
    val bmp = tryLoadFromUri(artUri)
    if (bmp != null) return bmp

    // Fallback: pakai disk cache yang sudah dibuat Full Player
    // Path: {filesDir}/artwork/{songId}.webp — selalu ada jika user sudah lihat Full Player
    if (songId > 0) {
        val webpFile = File(service.filesDir, "artwork/$songId.webp")
        if (webpFile.exists() && webpFile.length() > 0) {
            return BitmapFactory.decodeFile(webpFile.absolutePath)
        }
        // Jika belum ada di disk, minta ArtworkCacheManager ekstrak sekarang
        return artworkCacheManager.getOrExtract(songId)?.let {
            BitmapFactory.decodeFile(it)
        }
    }
    return null
}
```

Ini menggunakan `ArtworkCacheManager` (referensi dari service) yang sudah ada. Tidak perlu komponen baru.

### Patch 2 (Wajib): Hapus blacklist permanen `noArtworkUris`

Ganti `noArtworkUris` (yang permanen) dengan rate-limit sederhana: jangan retry lebih dari sekali per 30 detik untuk URI yang sama, bukan blacklist selamanya.

```kotlin
// Ganti noArtworkUris dengan timestamp terakhir gagal
private val failedUriTimestamps = HashMap<String, Long>()

// Di refresh():
val lastFail = failedUriTimestamps[artUri] ?: 0L
val recentlyFailed = (System.currentTimeMillis() - lastFail) < 30_000L
val hasCached = artUri == null || artworkCache.get(artUri) != null || recentlyFailed

// Di refreshAsync(), jika bmp==null:
failedUriTimestamps[artUri] = System.currentTimeMillis()
// Hapus entry ini saat track berganti (di refresh() setelah track change)
```

### Patch 3 (Wajib): Pass `songId` ke notification pipeline

Ubah `TrackMapper.currentTrackMap()` agar juga menyertakan `songId` di map yang dikembalikan, sehingga `getCurrentTrack()` di `PlaybackNotificationManager` bisa membaca `songId` untuk fallback.

```kotlin
// TrackMapper.kt — tambahkan "songId" ke hasil map
return songMap + mapOf(
    "index"          to index,
    "artworkUri"     to artUri,
    "nextTrackIndex" to nextTrackIndex,
    "songId"         to (songMap["id"] as? Number)?.toInt(),  // ← tambahkan ini
)
```

### Patch 4 (Disarankan): Fix `refreshAsync()` di `ensureMediaForeground()`

Capture track sebelum dipanggil, bukan re-evaluate dari default parameter:

```kotlin
fun ensureMediaForeground() {
    // ...
    val track = getCurrentTrack()          // ← capture sekali
    val artUri = track?.get("artworkUri") as? String
    val songId = (track?.get("songId") as? Number)?.toInt() ?: 0
    val notification = buildNotification(getSession(), track, getIsPlaying(), bitmap = null)
    startForegroundWith(notification)
    if (artUri != null || songId > 0) refreshAsync(artUri, songId, track, getIsPlaying())
}
```

---

## 8. Logging yang Direkomendasikan (Sementara)

Tambahkan di `loadBitmap()` dan `refreshAsync()` untuk verifikasi di device:

```kotlin
Log.d("NotifArtwork", "load artUri=$artUri songId=$songId")
Log.d("NotifArtwork", "ContentResolver result: ${if(bmp!=null) "OK" else "NULL"}")
Log.d("NotifArtwork", "Disk fallback: ${webpFile.path} exists=${webpFile.exists()}")
Log.d("NotifArtwork", "Final bitmap: ${if(bmp!=null) "${bmp.width}x${bmp.height}" else "NULL"}")
```

Dan di `refresh()`:
```kotlin
Log.d("NotifArtwork", "refresh: artUri=$artUri cached=${artworkCache.get(artUri)!=null} blacklisted=${artUri in noArtworkUris}")
```
