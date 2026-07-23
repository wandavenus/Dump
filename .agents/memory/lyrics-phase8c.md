---
name: Phase 8C Lyrics Architecture
description: Single-source-of-truth refactor untuk lyrics subsystem — cache consolidation, isEmbedded flag, centralized 429 handling.
---

# Phase 8C Lyrics Architecture

## Rule
`LyricsCacheManager` adalah satu-satunya cache untuk lyrics. Jangan tambahkan cache lagi di `LyricsService` atau lapisan lain di atas `LyricsFetchManager`.

## isEmbedded flag
`LyricsProviderResult.isEmbedded` (bool, default false) menentukan apakah sumber adalah tag embedded. Hanya `EmbeddedProvider` yang set `isEmbedded: true`. Jangan pakai string matching pada `providerName` untuk detect embedded source.

## 429 Handling
`ProviderHttp.get()` dan `.post()` otomatis memanggil `ProviderRateLimiter.instance.markRateLimited(providerName)` dan return null saat 429. Provider tidak perlu handle 429 manual — jika ditambahkan provider baru, jangan duplikasi pattern ini.

**Why:** Sebelumnya 4+ provider masing-masing duplikasi 3-4 baris 429 check dengan inkonsistensi (Kugou double-check, NetEase skip search step).

## Providers yang masih punya per-provider isLimited() check
kugou, kuwo, netease, qq_music masih punya `if (ProviderRateLimiter.instance.isLimited(name)) return null;` di awal fetch() — ini intentional safety fallback untuk call langsung di luar _runParallel (yang sudah filter). Jangan hapus.
