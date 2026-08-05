# Native High-Quality Color Extraction Engine

**Tanggal:** 24 Juli 2026
**Versi:** 2.0.0
**Status:** Spesifikasi implementasi aktif Android
**Legacy predecessor:** `palette_generator_plus` (Dart-side MMCQ via isolate)

---

## Algoritma yang Dievaluasi

| Algoritma | Kualitas | Performa | Kompleksitas | Kesimpulan |
|---|---|---|---|---|
| **Android `androidx.palette`** (MMCQ) | ★★★★ | ★★★★★ | Rendah | ✅ **Dipilih** |
| Custom C++ K-Means | ★★★★★ | ★★★ | Sangat Tinggi | ❌ Overengineered |
| Color Thief (Kotlin MMCQ) | ★★★★ | ★★★★ | Sedang | ❌ Duplikat fungsi Palette API |
| libimagequant | ★★★★★ | ★★★ | Sangat Tinggi | ❌ Dependensi C besar, build lama |
| OpenCV clustering | ★★★★ | ★★★ | Tinggi | ❌ Library berat, overkill |
| `palette_generator_plus` (legacy) | ★★★ | ★★★ | Rendah | ❌ Tidak lagi dipakai |

---

## Kenapa `androidx.palette` Dipilih

1. **Kualitas sudah sangat baik** — MMCQ (Modified Median Cut Quantization) adalah algoritma mature yang digunakan oleh Google/Android di seluruh ekosistem Material Design. Hasil quantization-nya clean dan representatif.

2. **Perbaikan kualitas utama ada di selection algorithm** — bukan hanya di
   quantizer. Pipeline native menggabungkan skor berbasis populasi, clustering
   OKLab, dan pemilihan role berbasis coverage/diversity untuk menjaga family
   warna nyata seperti navy, beige, skin tone, dan neutral tone.

3. **Native Android, tanpa decode Dart** — tidak ada serialisasi bytes ke Dart
   isolate dan tidak ada `MemoryImage` decode di Dart. Semua ekstraksi berjalan
   di thread Kotlin/JVM background yang sudah ada.

4. **Baca langsung dari ArtworkCacheManager** — artwork sudah ada di disk sebagai WebP. Tidak ada transfer bytes lewat MethodChannel (hanya `songId: Int` yang dikirim, bukan raw bytes).

5. **Batas kerja sesuai target device** — bitmap hasil decode dibatasi maksimal
   256×256 px per sisi, lalu AndroidX Palette menghasilkan maksimal 96 swatch.
   Tidak ada klaim waktu tetap; durasi bergantung pada cache artwork, decode,
   dan beban executor.

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
    │  ← Hitung sampleSize (power-of-2) agar tiap sisi ≤ 256 px
    │  ← Pass 2: decode dengan inSampleSize, Config = ARGB_8888
    │
    ▼
Palette.from(bitmap).maximumColorCount(96).clearFilters().generate()
    │  ← MMCQ quantization → hingga 96 candidate swatches
    │  ← clearFilters(): tidak buang reds/blacks/whites (shader butuh full spectrum)
    │
    ▼
selectBestFive(palette)
    │  ← Filter chromatic candidates dan skor population-led
    │  ← Merge family dengan OKLab distance < 0.15
    │  ← Pilih role dari maksimal 32 cluster teratas
    │  ← Neutral-dominance correction
    │  ← Derive secondary/accent/highlight/shadow bila diperlukan
    │
    ▼
List<Int> [primary, secondary, accent, highlight, shadow]
    │
    ▼ (via MethodChannel)
NativePaletteService (Dart)
    │  ← Konversi ke List<Color>
    │  ← Simpan ke LRU cache (256 entri)
    │  ← Debounced persist ke palette_cache_v<native-version>.json
    │
    ▼
fluid.frag shader (tidak diubah)
```

---

## Palette Selection Strategy

### Langkah 1 — Filter kandidat chromatic

Untuk pemilihan role chromatic, kandidat harus memenuhi:

- `saturation >= 0.10`
- `lightness` berada pada `0.06..0.93`

Near-neutral swatch tidak langsung dibuang dari pipeline: seluruh daftar Palette
tetap diperiksa pada langkah neutral-dominance correction agar background putih,
abu-abu, atau hitam yang benar-benar dominan dapat menjadi primary.

### Langkah 2 — Population-led perceptual scoring

```
score = (0.90 × popFactor + 0.10 × sat^0.8)
        × lightnessFactor × darkBonus

lightnessFactor = max(0.05, 1.0 − |lightness − 0.50| × 0.9)
popFactor       = log10(population + 1) / log10(maxPopulation + 1)
darkBonus       = 1.20 jika lightness < 0.25, selain itu 1.0
```

- Populasi adalah sinyal utama agar background besar tetap menjadi mood utama.
- Saturasi memberi boost moderat, bukan mengalahkan background yang dominan.
- Tidak ada center crop atau spatial/center weighting.

### Langkah 3 — OKLab clustering

Swatch yang berdekatan secara perseptual digabung dengan greedy clustering.
Jarak dihitung dalam OKLab dan threshold `0.15`. Population dan score seluruh
swatch yang bergabung dijumlahkan; representative tetap merupakan swatch nyata
dengan score individual tertinggi, bukan RGB average sintetis.

### Langkah 4 — Coverage/diversity role selection

Maksimal 32 cluster teratas dipakai untuk role selection:

- `primary`: cluster dengan total score tertinggi.
- `secondary`: cluster berikutnya yang menyeimbangkan area dan jarak
  perseptual dari role yang sudah dipilih.
- `accent`: cluster berikutnya dengan bobot diversity lebih besar.

Jika hanya satu atau dua family bermakna, valid family dipertahankan. Role yang
hilang diturunkan dari primary; hasil tidak diganti dengan tiga named swatch
yang tidak berkaitan.

### Langkah 5 — Neutral-dominance correction

Swatch near-neutral (`saturation < 0.12`) dari seluruh Palette dapat menggantikan
primary jika populasinya lebih dari dua kali total population cluster chromatic
primary. Ini mencakup near-black dan near-white.

### Langkah 6 — Highlight dan shadow

Cluster tersisa dapat dipakai jika:

- highlight: `lightness > 0.55`, `saturation > 0.10`;
- shadow: `lightness < 0.45`, `saturation > 0.08`;
- hue berada dalam `120°` dari hue primary.

Untuk primary neutral atau jika tidak ada kandidat yang sesuai, warna diturunkan
dari primary.

### Langkah 7 — Fallback chain

Jika tidak ada kandidat chromatic, gunakan named swatches AndroidX:
`vibrant → darkVibrant → lightVibrant → muted → darkMuted → lightMuted → dominant`

Output fallback selalu 5 warna:
`[0xFF2B313A, 0xFF4E657D, 0xFF7B8794, 0xFFABBED4, 0xFF121821]`

---

## Performance Optimizations

| Optimasi | Detail |
|---|---|
| **Two-pass BitmapFactory decode** | Pass 1 bounds-only (no pixel alloc), Pass 2 dengan `inSampleSize` yang tepat |
| **ARGB_8888 config** | Mempertahankan gradient artwork tanpa banding format 565 |
| **256×256 target size** | Batas decode per sisi untuk membatasi memory dan kerja quantization |
| **ArtworkCacheManager reuse** | Artwork sudah di disk; tidak perlu MediaMetadataRetriever lagi di banyak kasus |
| **Bounded executor** | Berjalan di `artworkExecutor` (2 threads, queue 48) — penolakan queue dikembalikan sebagai `palette_busy` |
| **In-flight dedup (Dart)** | Concurrent call untuk `songId` yang sama share satu Future |
| **LRU cache 256 entries** | Hot palettes (recently played, album cards) selalu synchronous |
| **Disk persistence** | Debounced 800ms atomic write ke cache versi native → palettes survive app kill |
| **songId-only channel call** | Tidak ada byte transfer lewat MethodChannel (tidak seperti `getArtwork` yang kirim raw bytes) |

---

## Known Limitations

1. **Android-only** — di web / non-Android, selalu return hardcoded fallback. Web preview tetap pakai fallback gradient (behavior ini sudah ada sebelumnya juga).

2. **Artwork belum di-cache = blocking** — `ArtworkCacheManager.getOrExtract()` bisa trigger MediaMetadataRetriever jika artwork belum pernah di-cache. Ini terjadi hanya sekali per song. Setelah WebP tersimpan, semua ekstraksi berikutnya instant.

3. **MMCQ bukan K-Means** — MMCQ lebih deterministik dan lebih cepat dari K-Means, tapi pada artwork dengan gradient smooth mungkin menghasilkan candidate yang lebih sedikit dibanding K-Means dengan random init. Untuk musik pada umumnya, MMCQ sudah lebih dari cukup.

4. **Monochrome artwork** — artwork hitam-putih atau near-monochrome dapat
   memakai dominant neutral sebagai primary; supporting roles diturunkan dari
   primary bila cluster chromatic tidak cukup.

---

## Future Improvement Opportunities

1. **Queue coalescing native** — deduplikasi request bersamaan untuk `songId`
   yang sama di sisi bridge agar burst palette tidak mengulang kerja.

2. **Artwork-aware extraction** — deteksi genre/style dari artwork (misal: anime vs portrait vs landscape) dan adjust scoring weights accordingly.

3. **Direct palette tests** — tambah test untuk scoring, clustering, neutral
   correction, output 5 warna, queue rejection, dan lifecycle completion.

4. **Remove legacy harmony helpers** — pindahkan helper harmony yang tidak
   dipakai production ke benchmark/test atau hapus.

5. **iOS native** — implementasi equivalent menggunakan Core Image / UIKit di Objective-C/Swift untuk parity kualitas di iOS.
