# Native High-Quality Color Extraction Engine

**Tanggal:** 24 Juli 2026  
**Versi:** 1.4.0  
**Menggantikan:** `palette_generator_plus` (Dart-side MMCQ via isolate)

---

## Algoritma yang Dievaluasi

| Algoritma | Kualitas | Performa | Kompleksitas | Kesimpulan |
|---|---|---|---|---|
| **Android `androidx.palette`** (MMCQ) | ★★★★ | ★★★★★ | Rendah | ✅ **Dipilih** |
| Custom C++ K-Means | ★★★★★ | ★★★ | Sangat Tinggi | ❌ Overengineered |
| Color Thief (Kotlin MMCQ) | ★★★★ | ★★★★ | Sedang | ❌ Duplikat fungsi Palette API |
| libimagequant | ★★★★★ | ★★★ | Sangat Tinggi | ❌ Dependensi C besar, build lama |
| OpenCV clustering | ★★★★ | ★★★ | Tinggi | ❌ Library berat, overkill |
| `palette_generator_plus` (lama) | ★★★ | ★★★ | Rendah | ❌ Dart isolate overhead, seleksi naif |

---

## Kenapa `androidx.palette` Dipilih

1. **Kualitas sudah sangat baik** — MMCQ (Modified Median Cut Quantization) adalah algoritma mature yang digunakan oleh Google/Android di seluruh ekosistem Material Design. Hasil quantization-nya clean dan representatif.

2. **Perbaikan kualitas sesungguhnya ada di selection algorithm** — bukan di quantizer. Dart `palette_generator_plus` menggunakan algoritma yang sama (MMCQ) tapi dengan seleksi warna yang naif (`swatches[0], [1], [2]`). Dengan selection algorithm baru, kualitas meningkat signifikan tanpa perlu ganti quantizer.

3. **Native Android, zero Dart overhead** — tidak ada serialisasi bytes ke Dart isolate, tidak ada `MemoryImage` decode di Dart. Semua berjalan di JVM/Kotlin thread yang sudah ada.

4. **Baca langsung dari ArtworkCacheManager** — artwork sudah ada di disk sebagai WebP. Tidak ada transfer bytes lewat MethodChannel (hanya `songId: Int` yang dikirim, bukan raw bytes).

5. **Sub-5ms di Snapdragon 730** — target 15ms sangat mudah dicapai. Bitmap 100×100 → MMCQ 32 swatches → selection: total ~3–8ms.

6. **Zero dependency baru di native** — `androidx.palette:palette:1.0.0` adalah library AndroidX resmi yang sudah ada di Maven Central, tidak ada FetchContent/NDK baru yang diperlukan.

---

## Pipeline Ekstraksi

```
songId (Int)
    │
    ▼
ArtworkCacheManager.getOrExtract(songId)
    │  ← Cek WebP di {filesDir}/artwork/{songId}.webp
    │  ← Jika belum ada: MediaMetadataRetriever → encode WebP → save atomik
    │
    ▼
BitmapFactory.decodeFile(path)
    │  ← Pass 1: inJustDecodeBounds = true → dapatkan dimensi
    │  ← Hitung sampleSize (power-of-2) agar ≤ 100×100
    │  ← Pass 2: decode dengan inSampleSize, Config = RGB_565
    │
    ▼
Palette.from(bitmap).maximumColorCount(32).clearFilters().generate()
    │  ← MMCQ quantization → hingga 32 candidate swatches
    │  ← clearFilters(): tidak buang reds/blacks/whites (shader butuh full spectrum)
    │
    ▼
selectBestThree(palette)
    │  ← Scoring perceptual vibrancy per swatch
    │  ← Hue diversity enforcement (3 warna berbeda ≥ 30°)
    │
    ▼
List<Int> [argb1, argb2, argb3]
    │
    ▼ (via MethodChannel)
NativePaletteService (Dart)
    │  ← Konversi ke List<Color>
    │  ← Simpan ke LRU cache (256 entri)
    │  ← Debounced persist ke palette_cache.json
    │
    ▼
fluid.frag shader (tidak diubah)
```

---

## Palette Selection Strategy

### Langkah 1 — Filter

Buang swatch yang hampir hitam / putih / abu:
- `saturation < 0.12` → terlalu abu-abu
- `lightness < 0.10` → terlalu gelap  
- `lightness > 0.92` → terlalu terang

### Langkah 2 — Perceptual Vibrancy Scoring

```
score = sat^1.4 × lightnessFactor × (0.35 + 0.65 × popFactor)

lightnessFactor = max(0.05, 1.0 − |lightness − 0.45| × 1.6)
popFactor       = log10(population + 1) / log10(maxPopulation + 1)
```

- `sat^1.4`: reward warna vibrant, penalize warna muted
- `lightnessFactor`: prefer mid-range lightness (~0.45), penalize extremes
- `popFactor`: log-scale population weight — warna dominan diprioritaskan tanpa mendominasi sepenuhnya

### Langkah 3 — Hue Diversity Enforcement

Pick 3 warna dengan hue angular distance minimum, relax progressively:

```
threshold tries: [40°, 25°, 12°, 0°]
```

Untuk setiap threshold: iterasi swatches (sorted by score desc), pilih swatch jika hue distance dari semua swatch yang sudah dipilih ≥ threshold. Berhenti saat 3 warna terpilih.

Threshold `0°` = pilih berdasarkan score saja tanpa constraint diversity (last resort).

### Langkah 4 — Fallback Chain

Jika candidates kosong setelah filter → gunakan Palette API's named swatches:
`vibrant → darkVibrant → lightVibrant → muted → darkMuted → lightMuted → dominant`

Jika itu juga kosong → hardcoded fallback:
`[0xFF2B313A, 0xFF4E657D, 0xFF7B8794]`

---

## Performance Optimizations

| Optimasi | Detail |
|---|---|
| **Two-pass BitmapFactory decode** | Pass 1 bounds-only (no pixel alloc), Pass 2 dengan `inSampleSize` yang tepat |
| **RGB_565 config** | Setengah memory vs ARGB_8888; palette scan tidak butuh alpha channel |
| **100×100 target size** | Cukup untuk capture semua colour region penting; 10× lebih kecil dari WebP cache (1000×1000) |
| **ArtworkCacheManager reuse** | Artwork sudah di disk; tidak perlu MediaMetadataRetriever lagi di banyak kasus |
| **Bounded executor** | Berjalan di `artworkExecutor` (2 threads, queue 48) — tidak bisa membanjiri system |
| **In-flight dedup (Dart)** | Concurrent call untuk `songId` yang sama share satu Future |
| **LRU cache 256 entries** | Hot palettes (recently played, album cards) selalu synchronous |
| **Disk persistence** | Debounced 800ms write → palettes survive app kill, tidak perlu ekstraksi ulang di cold start |
| **songId-only channel call** | Tidak ada byte transfer lewat MethodChannel (tidak seperti `getArtwork` yang kirim raw bytes) |

---

## Known Limitations

1. **Android-only** — di web / non-Android, selalu return hardcoded fallback. Web preview tetap pakai fallback gradient (behavior ini sudah ada sebelumnya juga).

2. **Artwork belum di-cache = blocking** — `ArtworkCacheManager.getOrExtract()` bisa trigger MediaMetadataRetriever jika artwork belum pernah di-cache. Ini terjadi hanya sekali per song. Setelah WebP tersimpan, semua ekstraksi berikutnya instant.

3. **MMCQ bukan K-Means** — MMCQ lebih deterministik dan lebih cepat dari K-Means, tapi pada artwork dengan gradient smooth mungkin menghasilkan candidate yang lebih sedikit dibanding K-Means dengan random init. Untuk musik pada umumnya, MMCQ sudah lebih dari cukup.

4. **Monochrome artwork** — artwork hitam-putih atau near-monochrome akan melewati filter saturation, sehingga fallback chain digunakan. Hasilnya tetap swatch terbaik dari Palette API, bukan warna vivid. Ini expected behavior.

---

## Future Improvement Opportunities

1. **Oklab/CIECAM scoring** — ganti HSL scoring dengan perceptual color space (Oklab) untuk hue distance yang lebih akurat secara perseptual.

2. **Artwork-aware extraction** — deteksi genre/style dari artwork (misal: anime vs portrait vs landscape) dan adjust scoring weights accordingly.

3. **Palette versioning** — tambahkan version key ke `palette_cache.json` sehingga saat algorithm berubah, cache lama bisa diinvalidate secara selektif.

4. **K-Means hybrid** — untuk artwork dengan distribusi warna yang sangat tidak merata, K-Means post-processing bisa memperbaiki cluster centroid setelah MMCQ initial quantization.

5. **iOS native** — implementasi equivalent menggunakan Core Image / UIKit di Objective-C/Swift untuk parity kualitas di iOS.
