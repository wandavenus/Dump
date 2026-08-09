# Artwork raw-copy JPEG + extraction threads (1.5.19)

Scope E-A + E-B + E-C: mempercepat **ekstraksi/decode artwork pertama kali**
(opposite dari 1.5.18 yang mempercepat prefetch *path*).

## E-A — raw-copy JPEG kecil (ArtworkCacheManager.kt)

Sebelumnya tiap cache-miss: `extractRawBytes` → `decodeScaledBitmap` (decode penuh)
→ `saveAsWebP` (encode WebP lossy 85). Untuk mayoritas library yang art-nya
JPEG ≤1000px, decode+encode ini makan 100–300 ms CPU per lagu di mid-range
(Snapdragon 730) dan *menurunkan kualitas* (double compression).

Sekarang:
- `isJpeg(raw)` — cek SOI marker (FF D8 FF).
- `jpegFitsLimit(raw)` — bounds-only decode (inJustDecodeBounds, tanpa alokasi
  pixel) memastikan gambar valid & ≤ MAX_ARTWORK_SIZE.
- `saveRaw(raw, target)` — tulis bytes asli atomik (tmp + rename).
- Jalur lama (`saveAsWebP`) dipakai untuk non-JPEG / gambar > 1000px.

**Penting**: file cache **tetap berekstensi `.webp`** — ini dipakai untuk
bookkeeping LRU (`cleanupIfNeeded` filter `f.extension == "webp"`, begitu juga
`cacheCount`/`cacheSizeBytes`). Pembaca (Flutter `FileImage`, `BitmapFactory`)
men-sniff magic bytes isi file, bukan ekstensi → payload JPEG ter-decode benar
end-to-end. Jangan "perbaiki" ekstensi jadi `.jpg` tanpa mengubah filter LRU.

`jpegFitsLimit` sengaja pakai bounds-decode (bukan cuma magic bytes): JPEG
korup (magic valid, payload rusak) tidak boleh masuk cache mentah.

## E-B — thread ekstraksi 2 → 3 (MainActivity.kt)

`artworkExecutor` naik dari 2 ke 3 worker. Alasan: prefetch batch F-D (1.5.18)
sudah jalan 2-concurrent, slot ketiga menjaga request scroll/ganti-queue tidak
meng-stall batch di perangkat mid-range. Queue tetap 48, masih bounded — tidak
berlomba dengan audio decode/UI.

## E-C — hapus getArtwork (bytes)

`getArtwork` (MethodChannel, kembalikan Uint8List bytes) tidak pernah dipanggil
Dart — semua jalur pakai `getArtworkPath` → file cache. Yang dihapus:
- Kotlin: case `"getArtwork"` di `setupMediaStoreChannel` + fungsi private
  `getArtwork()` di MainActivity (duplikat `ArtworkCacheManager.extractRawBytes`).
- Dart: `MediaStoreService.getArtwork` + `_loadArtwork` + `_trimArtworkCache` +
  `_artworkCache` + `_maxArtworkCacheEntries` + `clearArtworkCache` + import
  `dart:collection` (cuma dipakai LinkedHashMap itu).

Lesson: cek `grep -rn 'getArtwork\b' lib/ test/` dulu sebelum hapus native —
`getArtworkPath` mengandung substring `getArtwork`, jadi pola harus pakai
word-boundary agar tidak false positive.

## Validasi

- `flutter analyze lib test` → No issues found.
- `flutter test` → 58/58 pass.
- Kotlin compileDebugKotlin dicoba via Gradle (daemon pertama mati di sandbox;
  `--no-daemon -Dorg.gradle.jvmargs=-Xmx2G` dipakai untuk retry).
