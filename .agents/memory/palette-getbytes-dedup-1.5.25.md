# Palette / getBytes dedup audit 1.5.25

## Verdict: jalur palette SUDAH terdedup di semua layer (tidak ada baca-disk ganda)

1. **Dart `NativePaletteService._pending`** — concurrent `get(songId)` berbagi satu Future.
2. **Native `NativePaletteBridge.inFlightBySongId`** — concurrent channel call `extractPalette` untuk lagu sama di-coalesce ke satu `InFlightJob`; kedua pemanggil tetap dapat hasil.
3. **`ArtworkCacheManager.getOrExtract` per-song lock** — ekstraksi MediaStore untuk lagu sama terserialisasi; re-check di dalam lock setelah lock dipegang.
4. **`playback_manager._prefetchingSongs`** (+ cap `_maxConcurrentPrefetches = 2`) — prefetch palette tidak dobel.
5. **2-pass decodeFile di `extractColors`** (bounds + full, `PALETTE_TARGET_SIZE = 256`) — standar, hanya sekali per ekstraksi (terdedup).

Catatan: baca file yang sama oleh Flutter ImageCache (FileImage) DAN BitmapFactory (palette) secara bersamaan adalah dua konsumen berbeda yang memang harus decode sendiri — bukan bug, inheren arsitektur.

## Gap yang ditemukan

**`ArtworkRepository.getBytes` = dead code (0 pemanggil di lib/test/android; `PaletteExtractor` sudah tidak ada).** Tapi baca filenya (`File.readAsBytes`) tidak punya dedup in-flight — dua pemanggil konkuren = 2× baca disk untuk file sama.

### Fix (1.5.25, murni Dart)

`getBytes` di-refactor: `_bytesInFlight` map (pola identik `_inFlight` di `getPath`) — pemanggil konkuren untuk songId sama berbagi satu read future; owner's `finally` yang menghapus entry. `evict()` ikut membersihkan `_bytesInFlight`. LRU `_bytes` dan perilaku error (evict + re-extract saat file stale) tidak berubah.
