# Investigasi Bug Artwork Notification Terlambat Berganti Saat Crossfade

## Tujuan

Cari akar penyebab mengapa artwork pada Notification Player terlambat
berganti ketika terjadi crossfade.

Perlu dicatat:

-   Crossfade audio berjalan normal.
-   Lagu berikutnya sudah mulai diputar.
-   Namun artwork Notification masih menampilkan lagu sebelumnya selama
    beberapa saat.
-   Bug ini mirip dengan masalah sinkronisasi Full Player yang
    sebelumnya sudah diperbaiki.

Jangan langsung memperbaiki kode. Temukan root cause terlebih dahulu.

------------------------------------------------------------------------

# 1. Bandingkan Dengan Fix Full Player

Cari commit atau perubahan yang sebelumnya memperbaiki sinkronisasi Full
Player.

Bandingkan:

-   event yang dipakai
-   timing update
-   source of truth
-   queue transition
-   current track
-   active player
-   crossfade controller

Cari apakah Notification masih memakai flow lama.

------------------------------------------------------------------------

# 2. Audit Timeline Crossfade

Buat timeline lengkap mulai dari:

-   next track dipilih
-   preload selesai
-   crossfade dimulai
-   active player berpindah
-   MediaSession berubah
-   currentTrack berubah
-   notification refresh
-   artwork request
-   artwork selesai dimuat
-   notification di-update

Tunjukkan urutan sebenarnya dari kode.

------------------------------------------------------------------------

# 3. Audit Source of Truth

Pastikan Notification mengambil artwork dari track yang benar.

Verifikasi apakah artwork diambil berdasarkan:

-   queue index
-   currentTrackMap()
-   activePlayer
-   MediaSession current item
-   CrossfadeController
-   playback state

Cari apakah Notification membaca state yang masih lama.

------------------------------------------------------------------------

# 4. Audit Event Selama Crossfade

Telusuri seluruh callback yang terjadi saat crossfade:

-   onMediaItemTransition()
-   onPositionDiscontinuity()
-   onIsPlayingChanged()
-   onPlaybackStateChanged()
-   QueueSync
-   TransportState
-   Crossfade callbacks

Pastikan event yang memicu Notification berasal dari track yang sudah
aktif, bukan track yang sedang fade-out.

------------------------------------------------------------------------

# 5. Audit Generation

Periksa apakah generation check pada artwork menyebabkan artwork baru
tertunda.

Verifikasi:

-   artwork generation
-   notification generation
-   crossfade generation
-   callback yang dibatalkan

Cari kemungkinan callback lama masih menang.

------------------------------------------------------------------------

# 6. Audit Queue State

Periksa kapan:

-   currentTrackMap()
-   currentQueueIndex
-   active player
-   MediaItem

berubah.

Pastikan artwork Notification tidak membaca queue index lama selama
crossfade.

------------------------------------------------------------------------

# 7. Logging

Tambahkan logging sementara minimal:

-   currentTrack id
-   current artwork uri
-   active player
-   crossfade progress
-   queue index
-   notification refresh
-   artwork load start
-   artwork load finish
-   MediaSession current media item

Supaya terlihat kapan artwork mulai tertinggal.

------------------------------------------------------------------------

# Output

Jangan melakukan patch.

Buat laporan yang berisi:

1.  Timeline lengkap saat crossfade.
2.  Root cause yang sudah terbukti.
3.  File dan fungsi yang terlibat.
4.  Mengapa Full Player sudah sinkron tetapi Notification belum.
5.  Patch minimal yang diperlukan.
6.  Pastikan solusi tidak menambah latency maupun mengganggu performa
    crossfade.
