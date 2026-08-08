# Lib Services & Optimization Audit — 2026-08-08

> **Remediation update (8 Agustus 2026):** F-1, F-2, dan F-3 semuanya sudah
> diterapkan (lihat bagian **Remediation update** di bawah).

## Scope

Audit seluruh folder `lib/` (277 file Dart, ~37.3k baris) berfokus pada
**lapisan service/performance/memory/correctness** — melengkapi
`Flutter_Widget_Best_Practices_Audit_2026-08-08.md` yang sudah menilai sisi
UI/widget. Target device: Xiaomi Mi 9T (SD730 / Android 11 / MIUI 12).

Dimensi yang diperiksa: blocking main-isolate (sync I/O, parsing berat),
network layer (timeout/retry/cancellation), MethodChannel reliability,
cache memory/disk, dependency usage (dead weight APK), resource lifecycle
(Timer/Stream/Listener), dan duplikasi helper.

**Metode:** grep terarah di `lib/` (compute/Isolate/jsonDecode/http/timeout/
Timer/StreamController/sync-IO/package imports) + baca manual file kunci
(`ProviderHttp`, `MediaStoreService`, `ArtworkRepository`,
`NativePaletteService`, `PlaybackManager`).

## Executive summary

Lapisan service sudah **sangat matang dan konsisten**: HTTP punya timeout +
retry + rate-limit + cancellation di satu wrapper, parsing JSON lagu
di-isolate-kan lewat `compute()`, artwork pakai 3-layer cache dengan
in-flight dedup, dan semua MethodChannel kritis sudah diberi timeout —
**kecuali satu jalur**. Tidak ada blocking sync I/O di hot path, tidak ada
Timer/Stream yang bocor. Ditemukan **2 temuan nyata (keduanya nol trade-off
untuk diperbaiki)** dan 1 catatan kosmetik.

## Findings

### F-1 (LOW) — 2 dependency di pubspec tidak terpakai sama sekali

| Field | Isi |
|---|---|
| Severity | LOW (dead weight, bukan bug) |
| File | `pubspec.yaml:19` (`cached_network_image ^3.4.1`), `pubspec.yaml:24` (`rxdart ^0.28.0`) |
| Deskripsi | `grep package:rxdart lib test` → **0**; `grep package:cached_network_image lib test` → **0**. Kedua dependency dideklarasikan tapi tidak pernah di-import di seluruh kode sumber. |
| Root cause | Sisa dari eksperimen awal; artwork pada akhirnya ditangani native (ArtworkRepository/MediaStore), streams memakai StreamController murni (bukan rxdart). |
| Dampak | Dependency tree lebih berat dari perlu: resolusi `flutter pub get` lebih lambat, APK ikut membawa kode mati (rxdart ± mem-pull beberapa lib; cached_network_image menarik `flutter_cache_manager` + `path_provider` + kawan-kawan yang mungkin sudah ada, tapi tetap graf yang tidak perlu). |
| Confidence | High (0 import di lib + test, `flutter analyze` clean → tidak ada referensi tersembunyi) |
| Rekomendasi | **Hapus kedua dependency dari `pubspec.yaml`**, jalankan `flutter pub get` (regenerate lockfile) + `flutter analyze`. Nol trade-off. |
| Risiko jika diabaikan | Rendah secara teknis; hanya beban maintenance + ukuran. |

### F-2 (MEDIUM) — Jalur artwork MethodChannel tanpa timeout (bisa hang selamanya)

| Field | Isi |
|---|---|
| Severity | MEDIUM (reliability, fail-open sudah ada di jalur lain) |
| File | `lib/services/media_store_service.dart:431` (`getArtwork`), `:503` (`getArtworkPath`), `:466` (`deleteSong`) |
| Deskripsi | `getSongs` (baris 184) diberi `.timeout(const Duration(seconds: 20))` dengan komentar eksplisit: *"a MethodChannel round-trip has no guaranteed response — this await would hang forever"*. FFmpeg bridge memakai `.timeout(3s)`. **Tapi `getArtwork`, `getArtworkPath`, dan `deleteSong` tidak punya timeout sama sekali.** |
| Root cause | Timeout ditambahkan dulu ke jalur startup kritis (getSongs/ffmpeg) saat bug hang ditemukan; jalur artwork jarang hang sehingga luput. |
| Dampak | Jika native side gagal reply (contended I/O saat scan besar, MIUI mematikan process work, dll.), Future artwork **tidak pernah resolve** → placeholder art bertahan selamanya, dan `_artworkCache` (LinkedHashMap<Future>) menampung future gantung sampai ke-trim LRU. Tidak crash, tapi tidak pernah pulih tanpa restart. |
| Confidence | High (komentar di `getSongs` dan `ffmpeg_decoder_bridge.dart:223` mengkonfirmasi risiko yang sama persis untuk MethodChannel secara umum) |
| Rekomendasi | Tambahkan `.timeout(const Duration(seconds: 8))` fail-open ke `null` pada `_loadArtwork` (kembalikan null → UI pakai placeholder, jalur retry alami via evict), dan timeout seragam pada `getArtworkPath`/`deleteSong`. Nol trade-off; konsisten dengan konvensi fail-open repo. |
| Risiko jika diabaikan | Placeholder artwork "kebekuan" pada perangkat kontended; tidak ada sinyal error di log. |

### F-3 (INFO) — Duplikasi helper `_formatTotalDuration` (kosmetik)

| Field | Isi |
|---|---|
| Severity | INFO (nilai kecil) |
| File | `lib/widgets/pages/album_sections.dart:75` dan `lib/widgets/pages/artist_sections.dart:41` |
| Deskripsi | Dua method `_formatTotalDuration(BuildContext)` identik kata demi kata (fold duration → `l.durationHoursMinutes`/`l.durationOnlyMinutes`), beda hanya sumber list (`widget.songs` vs `songs`). |
| Rekomendasi | Extract ke satu helper shared (mis. di `lib/extensions/` atau util durasi). Opsional — ini duplikasi 8 baris di 2 tempat, bukan sumber bug. |

## Positive findings (sudah benar — bukti nyata)

1. **Network layer solid** — `ProviderHttp` (dipakai semua 6 provider lyrics):
   read timeout 15s, retry maks 2x exponential backoff, 429 → rate-limit
   cooldown, cancellation token dihormati di setiap retry. Satu titik masuk
   untuk semua HTTP eksternal.
2. **Parsing berat di-isolate-kan** — `MediaStoreService.warmUp`/`getSongs`
   memakai `compute(_parseSongsJson, raw)` agar UI thread bebas saat
   first-frame startup.
3. **Disk persistence aman** — song list cache & palette cache keduanya
   memakai atomic write (`tmp` + `rename`), debounce (800ms), dan filename
   ber-version (palette) + backward-compat 3→5 warna.
4. **ArtworkRepository 3-layer** — memori LRU (300) → disk (pre-scanned set
   `_diskCachedIds` untuk lookup O(1) tanpa `statSync` per-scroll) → native
   extraction. In-flight dedup, `devicePixelRatio` di-resolve sekali
   (konsistensi cache key → anti-flicker cold start), prefetch terbatas
   dengan yield 120ms, `clearMemory()` siap untuk low-memory callback.
5. **MethodChannel anti-hang di jalur kritis** — `getSongs` 20s fail-open,
   FFmpeg `queryStatus` 3s; kedua jalur mengembalikan state aman saat
   timeout (list kosong / status default).
6. **Resource lifecycle lengkap** — Timer debounce/throttle di-cancel,
   StreamController broadcast di-close (lint `close_sinks` aktif),
   `addListener` selalu punya `removeListener` (scroll, ScrollToTop, LogService).
   Tidak ada `Future.delayed` tak berujung di lib.
7. **Tidak ada blocking sync I/O di hot path** — `existsSync()` hanya di
   startup sekali (cache probe), bukan per-frame/per-scroll.
8. **Error handling konsisten** — semua PlatformException/exception
   MethodChannel di-log via `LogService` dengan stack trace; tidak ada
   silent crash path yang ditemukan.

## Recommended order of work

1. **F-2**: timeout fail-open 8s pada `getArtwork`/`getArtworkPath`/`deleteSong`
   (paling bernilai — konsistensi reliabilitas).
2. **F-1**: hapus `rxdart` + `cached_network_image` dari pubspec (2 baris +
   `flutter pub get`).
3. **F-3**: dedup `_formatTotalDuration` (opsional, kosmetik).

Setiap item bisa berdiri sendiri; tidak ada saling ketergantungan.

## Verification

- Grep `package:rxdart` / `package:cached_network_image` → 0 hasil di `lib/` + `test/`.
- Grep `compute(` → `media_store_service.dart:77` (isolate parse) ✅.
- Grep `.timeout(` di lib → `getSongs` (20s), `ffmpeg_decoder_bridge` (3s), `ProviderHttp` (15s); **tidak ada** di `_loadArtwork`/`getArtworkPath`/`deleteSong`.
- Grep sync I/O (`*Sync`) di lib → hanya `existsSync()` probe startup + `artwork_repository` komentar; tidak ada di hot path.
- Baseline `flutter analyze` → **No issues found** (0 error/warning/info).
- Audit ini **tidak mengubah kode** — hanya laporan.

---

## Remediation update (8 Agustus 2026)

Semua temuan audit telah diperbaiki dalam satu sesi:

### F-2 — Timeout fail-open pada jalur artwork (DONE)

`lib/services/media_store_service.dart`:
- `_loadArtwork` (`getArtwork`): `.timeout(8s)` + `on TimeoutException` → `null`
  (placeholder), konsisten dengan komentar anti-hang di `getSongs`.
- `getArtworkPath`: `.timeout(8s)` + `on TimeoutException` → `null`.
- `deleteSong`: `.timeout(8s)` + `on TimeoutException` → `false`.

Nol trade-off; semua jalur MethodChannel kritis kini fail-open.

### F-1 — Hapus dependency tak terpakai (DONE)

`pubspec.yaml`: hapus `cached_network_image ^3.4.1` dan `rxdart ^0.28.0`.
`flutter pub get` → **14 dependency berubah**; `cached_network_image` bersih total
(termasuk transitif: flutter_cache_manager, octo_image, sqflite, uuid, dll).
`rxdart` masih muncul di lockfile sebagai **transitive** milik `audio_session`
(yang memang dipakai) — deklarasi direct sudah hilang, dan akan ikut hilang
sepenuhnya jika `audio_session` diganti/dibuang.

### F-3 — Consolidate `_formatTotalDuration` (DONE)

`lib/utils/duration_text.dart` (baru): helper shared `formatTotalDuration(...)`.
`album_sections.dart` & `artist_sections.dart` kini memanggil helper tersebut;
metode privat duplikat dihapus.

### Changelog & memory

- `pubspec.yaml` 1.5.16 → 1.5.17 + entri changelog 1.5.17.
- `.agents/memory/getsongs-timeout-hang.md` diperluas (artwork path juga
  dicakup).
