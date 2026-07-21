# Lanjutan Investigasi Artwork Notification (Sebelum Patch)

Laporan investigasi sebelumnya sudah menemukan beberapa penyebab yang
kuat. Namun sebelum melakukan implementasi patch, lakukan verifikasi
berikut agar root cause benar-benar terbukti.

## Tujuan

Pastikan apakah masalah utama berasal dari:

-   pipeline artwork,
-   event refresh Notification,
-   MediaSession,
-   atau kombinasi semuanya.

Jangan mengubah arsitektur sebelum seluruh poin berikut selesai
diverifikasi.

------------------------------------------------------------------------

# 1. Audit Seluruh Event Refresh Notification

Trace seluruh pemanggilan berikut:

-   refresh()
-   refreshAsync()
-   notify()
-   NotificationManager.notify()
-   startForeground()
-   updateNotification()
-   invalidate()
-   invalidateMediaSession()
-   MediaNotification.Provider

Buat urutan event secara lengkap sejak lagu berubah sampai notification
muncul.

------------------------------------------------------------------------

# 2. Audit MediaSession

Telusuri seluruh pemanggilan:

-   setMediaMetadata()
-   replaceMediaItem()
-   replaceMediaItems()
-   setMediaItems()
-   updateMediaMetadata()
-   player.replaceCurrentMediaItem()
-   player.setMediaItem()

Pastikan metadata benar-benar dikirim ulang setelah artwork selesai
dimuat.

Jangan berasumsi.

Buktikan dari kode.

------------------------------------------------------------------------

# 3. Verifikasi Refresh Setelah Bitmap Selesai

Tambahkan logging sementara.

Contoh:

-   Notification dibuat
-   Bitmap mulai di-load
-   Bitmap selesai di-load
-   Cache terisi
-   MediaMetadata diperbarui
-   Notification dibangun ulang

Jawab dengan bukti apakah notification memang di-refresh setelah bitmap
tersedia.

------------------------------------------------------------------------

# 4. Cari Missing Trigger

Jika bitmap berhasil dimuat tetapi notification tetap kosong, cari
apakah ada trigger yang hilang.

Contoh:

-   notify() tidak dipanggil
-   refresh() tidak dipanggil
-   MediaSession tidak update
-   NotificationManager tidak rebuild
-   callback berhenti di tengah

Tunjukkan lokasi file dan fungsi.

------------------------------------------------------------------------

# 5. Evaluasi Patch Sebelumnya

Untuk setiap patch yang diusulkan sebelumnya, jelaskan:

-   apakah benar memperbaiki akar masalah,
-   atau hanya workaround.

Terutama evaluasi:

## A. Fallback ke ArtworkCacheManager

Apakah ini benar root fix?

Atau hanya menyembunyikan bug karena Notification masih memakai pipeline
berbeda dengan Full Player?

## B. noArtworkUris

Evaluasi apakah blacklist permanen memang bug desain.

Jika iya, jelaskan solusi paling aman.

## C. songId

Pastikan apakah Notification memang membutuhkan songId sebagai
identifier utama.

------------------------------------------------------------------------

# Output

Jangan mengubah kode dulu.

Buat laporan akhir berisi:

1.  Event timeline lengkap.
2.  Apakah MediaSession benar-benar diperbarui setelah artwork tersedia.
3.  Apakah Notification benar-benar di-refresh.
4.  Root cause final yang sudah terbukti.
5.  Patch minimal yang benar-benar memperbaiki bug tanpa workaround.
6.  Patch mana yang wajib.
7.  Patch mana yang sebaiknya dibatalkan.

Semua kesimpulan harus berdasarkan bukti dari kode, bukan asumsi.
