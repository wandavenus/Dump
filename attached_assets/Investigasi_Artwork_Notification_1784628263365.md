# Investigasi Bug Artwork Notification Tidak Muncul

## Tujuan

Lakukan investigasi menyeluruh mengenai bug berikut:

-   Semua lagu memiliki artwork.
-   Artwork di **Full Player selalu tampil dengan benar**.
-   Namun artwork pada **MediaStyle Notification / Notification Player**
    kadang tidak muncul (kosong/default), dan hanya terjadi pada
    sebagian lagu atau pada kondisi tertentu.

Jangan melakukan perubahan kode sebelum penyebabnya ditemukan.

------------------------------------------------------------------------

# Fokus Investigasi

## 1. Telusuri seluruh alur artwork

Petakan flow lengkap mulai dari:

-   MediaStore
-   Repository artwork
-   Cache memory
-   Cache disk
-   Audio Engine
-   MediaSession
-   Media3
-   Notification
-   Notification Provider
-   Bitmap loader
-   Async loading
-   Callback update

Cari apakah notification menggunakan flow yang berbeda dibanding Full
Player.

------------------------------------------------------------------------

## 2. Bandingkan Full Player vs Notification

Cari seluruh lokasi yang mengambil artwork.

Bandingkan:

-   source bitmap
-   cache
-   ukuran bitmap
-   resize
-   decode
-   coroutine
-   thread
-   timing

Pastikan apakah notification menggunakan bitmap yang sama atau membuat
request baru.

------------------------------------------------------------------------

## 3. Cek race condition

Periksa kemungkinan:

-   notification dibuat sebelum artwork selesai di-load
-   MediaMetadata di-update terlalu cepat
-   bitmap belum tersedia saat notification pertama dibuat
-   callback tidak memicu refresh notification

Cari kemungkinan timing bug.

------------------------------------------------------------------------

## 4. Audit MediaSession

Periksa apakah:

-   MediaMetadata.artworkData
-   artworkUri
-   displayIcon
-   albumArt

diisi dengan benar setiap pergantian lagu.

Pastikan metadata benar-benar berubah saat track berubah.

------------------------------------------------------------------------

## 5. Audit Notification Provider

Periksa:

-   onUpdateNotification
-   createNotification
-   NotificationCompat.MediaStyle
-   MediaStyleNotificationHelper
-   MediaNotification.Provider
-   MediaNotificationManager

Cari apakah bitmap bisa menjadi null.

------------------------------------------------------------------------

## 6. Audit Artwork Cache

Periksa apakah:

-   cache key konsisten
-   cache miss
-   bitmap di-evict terlalu cepat
-   ukuran bitmap terlalu besar
-   decode gagal
-   recycle() dipanggil terlalu dini

------------------------------------------------------------------------

## 7. Audit Coroutine / Thread

Cari:

-   suspend function yang tidak di-await
-   coroutine dibatalkan
-   Dispatcher.IO → Main
-   lifecycle issue

------------------------------------------------------------------------

## 8. Audit Bitmap

Periksa:

-   ukuran bitmap
-   Config
-   recycled bitmap
-   mutable/immutable
-   decode exception

------------------------------------------------------------------------

## 9. Logging

Tambahkan logging sementara pada:

-   request artwork
-   cache hit/miss
-   decode bitmap
-   metadata update
-   notification update

Supaya terlihat:

-   artwork berhasil ditemukan atau tidak
-   notification menerima bitmap atau null
-   kapan notification dibuat
-   kapan metadata diperbarui

------------------------------------------------------------------------

# Output yang Diharapkan

Jangan langsung memperbaiki bug.

Berikan laporan yang berisi:

1.  Root cause yang sudah terbukti.
2.  Langkah reproduksi jika ada.
3.  File yang terlibat.
4.  Fungsi yang terlibat.
5.  Mengapa Full Player selalu benar tetapi Notification gagal.
6.  Apakah bug berasal dari:
    -   Media3
    -   Notification
    -   Cache
    -   Race condition
    -   Async loading
    -   Bitmap decode
    -   Metadata
    -   atau kombinasi beberapa faktor.
7.  Rencana patch yang paling aman tanpa trade-off.

Jangan membuat asumsi. Semua kesimpulan harus didukung bukti dari kode.
