# Audit Implementasi Crossfade — 2 Agustus 2026

## Kesimpulan

Arsitektur crossfade sudah tepat: seluruh overlap audio berjalan native di
`Media3PlaybackService` memakai dua `ExoPlayer`. Controller Dart hanya menjadi
stub kompatibilitas dan tidak menjalankan timer crossfade.

Setelah audit, ada tiga celah lifecycle yang perlu diperbaiki:

1. Pause atau stop ketika fade sedang berlangsung dapat meninggalkan player
   aktif dengan timeline satu item dan runnable fade yang masih terjadwal.
2. Perubahan durasi crossfade ketika fade sedang berlangsung memiliki risiko
   yang sama karena cancel tidak langsung membangun ulang queue aktif.
3. Target volume sebelumnya diambil sekali sebelum fade. Perubahan volume user
   selama overlap dapat tertimpa oleh target lama saat tick berikutnya atau saat
   fade selesai. Audio ducking juga perlu diterapkan ke kedua player, bukan
   hanya player aktif.

Ketiganya sudah diperbaiki.

## Bagian yang diaudit

- `CrossfadeController`
  - prewarm dan preload standby;
  - equal-power fade 16 ms;
  - promotion dan `promotionOwner`;
  - cancel/reset;
  - queue isolation untuk repeat-all;
  - MediaSession metadata switch;
  - artwork notification prewarm.
- `PreloadManager`
  - preload, prewarm, clear, release, dan reset index.
- `ActivePlayerProxy`
  - migrasi listener dan delegasi state ke player aktif.
- `QueueManager`
  - defer queue mutation saat crossfade;
  - incremental rebuild setelah promotion.
- `TransportCommands`
  - play/pause/stop;
  - skip next/previous;
  - set queue/track;
  - repeat/shuffle;
  - perubahan durasi crossfade.
- `Media3PlaybackService`
  - position ticker 200 ms;
  - audio focus loss/noisy event;
  - offload listener;
  - service teardown;
  - Bit-Perfect mutual exclusion.
- notification artwork dan MediaSession metadata.

## Invariant yang sudah benar

- `REPEAT_MODE_ONE` tidak menjalankan crossfade.
- Repeat-all tidak membuat queue[0] menyusup saat track lama selesai lebih awal.
- Player lama diisolasi menjadi tepat satu item sebelum fade.
- Repeat mode player lama dimatikan setelah promotion, sehingga state UI global
  tidak ikut berubah.
- Player lama dihentikan dan dibersihkan saat fade selesai atau dibatalkan.
- Skip saat fade membangun ulang queue aktif sebelum navigasi berikutnya.
- Audio focus loss dan headphone unplug membatalkan overlap dua player.
- MediaSession tetap memakai `ActivePlayerProxy`, bukan mengganti raw player.
- Artwork notifikasi diprewarm 1,5 detik sebelum promotion dengan dedup load.
- Audio offload diperlakukan tidak kompatibel dengan overlap dua player.
- Bit-Perfect Mode membatalkan crossfade dan melepaskan standby player.
- Shutdown membatalkan runnable crossfade sebelum player dilepas.

## Perubahan yang diterapkan

### 1. Cancel lifecycle

Pause, stop, dan perubahan durasi sekarang:

1. menyimpan status crossfade dan index track yang dipromosikan;
2. membatalkan runnable crossfade;
3. membersihkan standby;
4. membangun ulang full queue pada player aktif jika sebelumnya masih satu item.

Dengan begitu pause/resume, stop/start, dan perubahan setting tidak membuat
`next`/`previous` terkunci pada track yang sedang dipromosikan.

### 2. Target volume dinamis

Equal-power fade membaca target volume pada setiap tick 16 ms dan kembali
membaca target terbaru saat selesai. Perubahan volume user selama overlap tidak
lagi dikalahkan oleh nilai yang disimpan sebelum fade. Saat audio focus meminta
ducking, target dinamis memakai faktor duck yang sama untuk player lama dan baru,
sehingga fade tidak membatalkan ducking pada tick berikutnya.

## Catatan pengujian

Unit test crossfade yang sudah ada mencakup guard duration, repeat, standby,
promotion, cancel, dan pencegahan promotion ganda. Audit ini menambahkan
perilaku lifecycle pada implementasi yang dipakai oleh jalur transport.

Validasi lanjutan yang disarankan pada Xiaomi Mi 9T/K20:

- pause tepat saat fade 1–2 detik terakhir;
- stop dari notification ketika overlap berlangsung;
- ubah durasi dari 5 detik ke off saat overlap;
- ubah volume atau menerima audio ducking saat overlap;
- repeat-all dengan queue minimal 3 lagu;
- skip next/previous tepat saat promotion.
