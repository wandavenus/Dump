# Root Cause Analysis — "Putar Selanjutnya" Tidak Memainkan Lagu Dengan Benar

**Tanggal:** 23 Agustus 2026
**Commit:** `d4fffd8`
**Status:** Akar masalah TERKONFIRMASI lewat pembacaan kode (static trace).

## Fix status (2026-08-23)

Fix utama dan hardening **sudah diterapkan** (verifikasi statis; Kotlin tidak bisa
dikompilasi di environment ini — tanpa Android SDK):

- **FIXED — `TransportCommands.kt` (`"insertNext"`)**: kini memanggil
  `preloadManager.preloadNextTrack(force = true)` saat crossfade aktif, mengikuti pola
  `"appendToQueue"`. Aman saat promosi berjalan karena guard `< queue.size` di
  PreloadManager membuatnya early-return.
- **FIXED — `PreloadManager.kt` (guard staleness)**: cek `preloadedQueueIndex == nextIndex`
  diperkuat dengan verifikasi identitas konten via `mediaId`
  (`(id ?: path)` sesuai konvensi `MediaItemFactory`) — preload basi yang indeksnya
  kebetulan sama tidak lagi lolos.

Validasi runtime tetap disarankan: langkah 1–5 di bagian akhir dokumen ini.

---

## Gejala

Menekan tombol **"Putar Selanjutnya"** (context menu lagu → `AudioService.addToQueueNext`)
tidak memainkan lagu yang dipilih dengan benar saat lagu saat ini berakhir:
lagu lain yang malah terputar, dan/atau metadata (UI/notification) tidak cocok
dengan audio yang terdengar.

## Prasyarat Reproduksi

- **Crossfade aktif** (`crossfadeDuration > 0`). Tanpa crossfade, jalur auto-advance
  ExoPlayer membaca timeline yang sudah diperbarui → lagu yang benar terputar.
- Standby player sudah selesai preload lagu berikutnya (kondisi normal selama playback).

---

## Akar Masalah

Handler `"insertNext"` di `TransportCommands.kt` **tidak meng-invalidasi preload standby**
setelah mutasi queue — berbeda dari handler `"appendToQueue"` yang melakukannya.

```kotlin
// TransportCommands.kt:203-208
"insertNext" -> {
    val item = call.argument<Map<String, Any?>>("item")
        ?: run { result.success(null); return }
    queueManager.insertNext(item)
    // ❌ TIDAK ADA: preloadManager.preloadNextTrack(force = true)
    result.success(null)
}

// TransportCommands.kt:210-216 (pembanding — pola yang benar)
"appendToQueue" -> {
    ...
    queueManager.appendToQueue(item)
    if (crossfadeController.crossfadeDurationSec > 0f) preloadManager.preloadNextTrack(force = true)  // ✅
    result.success(null)
}
```

---

## Rantai Kegagalan Lengkap

1. Lagu A berputar, queue `[A, C, D]`, crossfade ON.
   `PreloadManager.preloadNextTrack()` memuat **C** ke standby; `preloadedQueueIndex = 1`.
2. User menekan "Putar Selanjutnya" pada lagu B:
   - Dart: optimistic insert `[A, B, C, D]` + `PlaybackManager.insertNext(B)`.
   - Native `QueueManager.insertNext`: queue otoritatif jadi `[A, B, C, D]` ✓,
     timeline player aktif dapat B di index 1 ✓,
     **standby masih berisi C** ✗ (tidak pernah dibersihkan/di-reload).
3. Menjelang akhir A, `CrossfadeController.maybeCrossfadeOut()` memanggil
   `preloadManager.preloadNextTrack()` (**non-forced**) — tapi guard staleness hanya
   membandingkan **indeks**, bukan isi:
   ```kotlin
   // PreloadManager.kt:73
   if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex) return
   ```
   `current.nextMediaItemIndex` = 1 (posisi baru B), `preloadedQueueIndex` = 1 → early-return.
   Preload basi C tetap tidak diganti. Justru inilah mengapa re-preload oportunistik
   tidak menyelamatkan kondisi ini.
4. `beginCrossfade()` (`CrossfadeController.kt:240`) membaca
   `nextIndex = preloadedQueueIndex` (= 1) dan **mempercayai isi standby == queue[1] (= B)**.
   Standby di-promosikan → **yang terputar adalah C**, bukan B.
5. Setelah promosi, bookkeeping menganggap lagu aktif = `queue[activeQueueIndex=1]` = B,
   padahal yang bersuara C. `rebuildPlayerQueue()` lalu membangun prefix/suffix
   di sekitar index 1 dengan asumsi yang salah → timeline & metadata bergeser satu posisi:
   UI/notification menampilkan judul yang tidak cocok dengan audio, urutan lanjutan meleset.

### Kasus mid-crossfade (sudah ditangani desain)

Insert saat fade sedang berjalan aman: `QueueManager.insertNext` menunda mutasi timeline
via `pendingPlayNextIndex` dan `rebuildPlayerQueue()` menerapkannya setelah promosi
(`CrossfadeController.kt:474` memanggil `preloadNextTrack(force = true)`). Guard
`if (current.mediaItemCount < queue.size) return` di `PreloadManager` juga membuat
pemanggilan forced saat promosi menjadi no-op yang aman — jadi fix di bawah tidak
berisiko untuk kasus ini.

---

## Rekomendasi Fix

**Fix utama** — tambahkan satu baris di handler `"insertNext"`:

```kotlin
"insertNext" -> {
    val item = call.argument<Map<String, Any?>>("item")
        ?: run { result.success(null); return }
    queueManager.insertNext(item)
    if (crossfadeController.crossfadeDurationSec > 0f) {
        preloadManager.preloadNextTrack(force = true)
    }
    result.success(null)
}
```

Sama seperti pola `appendToQueue`. Alternatif yang lebih murah:
`preloadManager.clearStandbyQueue()` tanpa re-preload (re-preload akan terjadi
di `maybeCrossfadeOut` menjelang akhir lagu).

**Fix sekunder (hardening)** — guard staleness `PreloadManager` sebaiknya memverifikasi
identitas konten, bukan hanya indeks:

```kotlin
val expectedId = queue[nextIndex]["id"]
val loadedOk  = (standby.currentMediaItem?.mediaId ?: "?") == "$expectedId"
if (!force && standby.mediaItemCount > 0 && preloadedQueueIndex == nextIndex && loadedOk) return
```

Dengan begiti kelas bug "preload basi dengan indeks kebetulan sama" tidak bisa
terulang lewat jalur mana pun di masa depan.

---

## Verifikasi Yang Disarankan (perangkat)

1. Crossfade ON (mis. 5 s), mainkan lagu pertama album, tunggu preload log
   `preloadNextTrack → [1] '<judul C>'`.
2. "Putar Selanjutnya" lagu B dari context menu.
3. Log native harus muncul: `preloadNextTrack(force) → [1] '<judul B>'`.
4. Biarkan lagu berjalan sampai crossfade → yang harus fade-in adalah **B**,
   UI/notification menampilkan B, dan queue lanjutan tetap benar.
5. Uji juga: shuffle ON + Putar Selanjutnya; insert saat crossfade sedang berjalan;
   repeat-one (bukan bagian jalur ini).
