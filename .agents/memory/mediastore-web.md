---
name: MediaStore web behavior
description: MediaStoreService melempar MissingPluginException di browser web; bukan bug — semua seksi harus menangani list kosong.
---

## Aturan
`MediaStoreService.getSongs()` dan `getArtwork()` memanggil platform channel Android (`musicplayer/media_store`). Di web/browser, method ini melempar `MissingPluginException` yang di-catch dan mengembalikan list kosong / null.

**Why:** App adalah Flutter web build yang dijalankan di browser untuk preview. MediaStore hanya tersedia di runtime Android.

**How to apply:** Setiap StatefulWidget yang memanggil `MediaStoreService` harus: (1) wrap dengan try/catch, (2) set loading=false di catch, (3) tampilkan empty state yang bersih (bukan error) saat list kosong. `SongArtwork` sudah menangani null artwork dengan fallback icon.
