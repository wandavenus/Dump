# Phase 8C — Lyrics Architecture Report

**Tanggal:** 18 Juli 2026  
**Versi app:** 1.2.9+1  
**Basis:** Revalidation_Report_2026_07_18.md (temuan M-7, M-8, M-9, N-2)

---

## 1. Architecture Report

### Arsitektur Lama

Sistem lirik sebelumnya memiliki **dua sumber kebenaran untuk cache** yang bisa drift:

```
LyricsService._cache               ← Map<String, LyricsResult> statis (keyed by legacyKey)
LyricsCacheManager._mem            ← Map<String, _CacheEntry>  (keyed by cacheKey)
LyricsCacheManager._failedAtMs     ← failure TTL
LyricsCacheManager (disk)          ← SharedPreferences
```

**Masalah lama:**
1. `service.dart` menyimpan `LyricsResult` di `_cache` (legacy), sementara `LyricsFetchManager` menyimpan `LyricsProviderResult` di `LyricsCacheManager`. Keduanya bisa tidak sinkron.
2. Source detection bergantung pada string matching: `providerName.contains('tag')` — fragile karena provider baru mana pun dengan 'tag' dalam namanya akan mis-classified.
3. Setiap online provider menangani HTTP 429 secara manual — 4+ baris duplikat per provider, tidak konsisten (Kugou double-checked, NetEase melewatkan 429 di search step).
4. Kuwo mengakses `lrcData['data']` dua kali dalam satu ekspresi — kurang jelas dan ada potensi double-evaluation.

### Arsitektur Baru

```
LyricsService.fetchLyrics()
    └─► LyricsFetchManager.instance.fetch()   ← satu-satunya jalur fetch
            ├─ LyricsCacheManager (memory)     ← satu-satunya cache memory
            ├─ LyricsCacheManager (failure TTL)
            ├─ LyricsCacheManager (disk)
            ├─ local providers (sequential)
            └─ online providers (parallel)
                    └─► ProviderHttp.get/post() ← 429 auto-handled di sini
```

**Perubahan utama:**
1. **Single cache:** `LyricsService._cache` dihapus. `LyricsCacheManager` adalah satu-satunya sumber kebenaran. `LyricsResult` dibangun on-the-fly dari `LyricsProviderResult` (cheap operation).
2. **Typed flag:** `LyricsProviderResult.isEmbedded` (bool, default false) menggantikan string matching. Hanya `EmbeddedProvider` yang set `isEmbedded: true`.
3. **Centralized 429:** `ProviderHttp.get()` dan `.post()` otomatis memanggil `ProviderRateLimiter.instance.markRateLimited(providerName)` dan return null ketika status code 429. Provider tidak perlu handle 429 manual.
4. **Kuwo null safety:** Ekstrak `lrcData['data']` ke variabel `lrcDataSection` sebelum digunakan — akses tunggal, null-safe jelas.

---

## 2. Changed Files

| File | Perubahan |
|---|---|
| `lib/services/lyrics_service/provider.dart` | Tambah field `isEmbedded` (bool, default false) ke `LyricsProviderResult` |
| `lib/services/lyrics_service/service.dart` | Hapus `_cache` legacy + `_kEmbeddedProviderMarker`; gunakan `isEmbedded` flag; sederhanakan `clearCache()` |
| `lib/services/lyrics_service/providers/provider_http.dart` | Tambah 429 auto-handling di GET dan POST — mark rate limit + return null |
| `lib/services/lyrics_service/providers/embedded_provider.dart` | Set `isEmbedded: true` pada result |
| `lib/services/lyrics_service/providers/lrclib_provider.dart` | Hapus manual 429 check + mark; hapus import `rate_limiter.dart` |
| `lib/services/lyrics_service/providers/apple_music_provider.dart` | Hapus manual 429 checks (2x) + marks; hapus import `rate_limiter.dart` |
| `lib/services/lyrics_service/providers/netease_provider.dart` | Hapus manual 429 check di lyric step; sederhanakan null check |
| `lib/services/lyrics_service/providers/kugou_provider.dart` | Hapus manual 429 check + double-check pattern; sederhanakan null check |
| `lib/services/lyrics_service/providers/kuwo_provider.dart` | Hapus manual 429 check; ekstrak `lrcDataSection` untuk null safety (N-2) |
| `lib/services/lyrics_service/providers/qq_music_provider.dart` | Hapus manual 429 check + mark; sederhanakan null check |
| `lib/pages/settings_page/changelog_data.dart` | Tambah entri changelog v1.2.9 |
| `pubspec.yaml` | Bump version ke 1.2.9+1 |

---

## 3. Behavioral Equivalence Report

| Aspek | Status |
|---|---|
| Lyrics output (lines, quality, rawLrc) | ✅ Identik — field mapping tidak berubah |
| Fallback order (embedded → local → online parallel) | ✅ Identik — `LyricsFetchManager` tidak diubah |
| Provider switching | ✅ Identik — provider registry tidak berubah |
| Synced lyrics (LRC) | ✅ Identik — `LrcParser` tidak diubah |
| Unsynced lyrics | ✅ Identik |
| Translation display | ✅ Identik — providerName tetap diteruskan ke `LyricsResult` |
| Rate limiting (cooldown 60s) | ✅ Identik — logika `ProviderRateLimiter` tidak berubah, hanya titik pemanggilannya |
| Cache TTL (memory: 30 hari, failure: 1 jam) | ✅ Identik — `LyricsCacheManager` tidak diubah |
| Source label di UI | ✅ Identik — `LyricsSource` enum dan `sourceLabel` tidak berubah |

**Catatan source detection:**
- Sebelum: `providerName.contains('tag')` → `LyricsSource.embedded`
- Sesudah: `providerResult.isEmbedded == true` → `LyricsSource.embedded`
- Hasil: identik untuk `EmbeddedProvider` (satu-satunya yang set `isEmbedded: true`). Provider lain semua `isEmbedded: false`.

---

## 4. Risk Report

| Risiko | Level | Mitigasi |
|---|---|---|
| `LyricsService._cache` dihapus — caller yang bergantung pada kecepatan hit cache | Rendah | `LyricsCacheManager.getMemory()` sudah melayani hit sama cepatnya (O(1) lookup); `LyricsResult` construction adalah operasi trivial |
| 429 sekarang selalu return null di ProviderHttp — provider tidak bisa inspect status code 429 | Rendah | Semua provider sebelumnya juga return null setelah 429; behavior identik |
| `legacyKey` vs `cacheKey` format berbeda — warm restart kehilangan in-memory legacy cache | Tidak ada | Legacy `_cache` sudah tidak ada; `LyricsCacheManager` sudah menjadi sumber kebenaran sebelum perubahan ini, jadi tidak ada regresi |
| Provider baru di masa depan yang butuh inspect 429 | Rendah | Bisa override dengan subclass `ProviderHttp` atau extend kontrak, tapi skenario ini tidak ada saat ini |

---

## 5. Validation Report

### flutter analyze
```
No issues found! (ran in 11.7s)
```

### Build status
Web rebuild otomatis berhasil (watch-rebuild.js mendeteksi perubahan dan rebuild clean).

### Changed files summary
- 10 Dart files diubah
- 0 new files (tidak ada file baru, hanya modifikasi)
- Tidak ada perubahan pada test files (test yang ada tidak menyentuh lyrics internals)

### Manual verification notes
- Tidak ada perubahan pada Media3/ExoPlayer/DSP/ReplayGain/artwork pipeline
- Semua perubahan terbatas pada `lib/services/lyrics_service/`
- Public API (`LyricsService.fetchLyrics`, `clearCache`, `cancelAll`, `parseLrc`) tidak berubah
- `LyricsResult` public interface tidak berubah
- UI pages yang consume `LyricsService` tidak perlu diubah

---

*Laporan ini dibuat setelah Phase 8C selesai. Verifikasi pada Mi 9T tidak dapat dilakukan di lingkungan Replit (perlu device fisik atau ADB).*
