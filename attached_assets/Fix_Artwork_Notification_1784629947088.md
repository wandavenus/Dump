# Implementasi Fix Artwork Notification

## Tujuan

Implementasikan seluruh perbaikan berikut. Jangan membuat workaround
sementara. Hasil akhir harus membuat Notification menggunakan pipeline
artwork yang sama kuatnya dengan Full Player.

------------------------------------------------------------------------

# 1. Perbaiki `loadBitmap()`

Refactor `PlaybackNotificationManager.loadBitmap()`.

Urutan pengambilan artwork harus menjadi:

1.  Coba `ContentResolver` (jalur yang ada sekarang).
2.  Jika gagal, gunakan pipeline yang sama dengan Full Player.
3.  Gunakan `ArtworkCacheManager` / `ArtworkRepository` sebagai
    fallback.
4.  Jangan mengembalikan `null` sebelum seluruh jalur fallback dicoba.

Jangan membuat pipeline decode baru jika sudah ada implementasi yang
dapat dipakai ulang.

------------------------------------------------------------------------

# 2. Hilangkan Blacklist Permanen

Perbaiki mekanisme `noArtworkUris`.

Blacklist permanen tidak boleh lagi menyebabkan artwork gagal muncul
sampai aplikasi direstart.

Gunakan mekanisme yang tetap mencegah retry berlebihan tetapi masih
memungkinkan retry ketika kondisi sementara (misalnya MediaStore belum
siap) sudah berubah.

------------------------------------------------------------------------

# 3. Gunakan `songId`

Jangan menambah field baru apabila `songId` (`id`) sudah tersedia.

Gunakan identifier yang sudah ada untuk mengakses artwork fallback.

------------------------------------------------------------------------

# 4. Jangan Gandakan Pipeline

Notification tidak boleh memiliki implementasi decode artwork sendiri
apabila sudah ada pipeline yang digunakan Full Player.

Sebisa mungkin gunakan implementasi yang sama sehingga:

-   Full Player
-   Mini Player
-   Notification
-   Lock Screen
-   Bluetooth
-   Android Auto

mengambil artwork dari sumber yang sama.

------------------------------------------------------------------------

# 5. Pertahankan Behavior Saat Ini

Tetap pertahankan:

-   startForeground() tepat waktu
-   asynchronous artwork loading
-   generation check
-   update notification setelah bitmap tersedia
-   performa yang baik saat next/previous cepat

Jangan menambah blocking operation di main thread.

------------------------------------------------------------------------

# 6. Validasi

Pastikan seluruh skenario berikut berhasil:

-   play pertama
-   next cepat berkali-kali
-   previous
-   shuffle
-   repeat
-   app cold start
-   background
-   foreground
-   lock screen
-   notification
-   file dari MediaStore
-   file yang memiliki embedded artwork

Artwork harus selalu muncul apabila file memang memiliki artwork.

------------------------------------------------------------------------

# Output

Setelah selesai, berikan laporan yang berisi:

1.  File yang diubah.
2.  Fungsi yang diubah.
3.  Ringkasan implementasi.
4.  Alasan teknis setiap perubahan.
5.  Dampak terhadap performa dan memori.
6.  Risiko kompatibilitas jika ada.

Pastikan implementasi tetap konsisten dengan arsitektur proyek dan tidak
menambah technical debt.
