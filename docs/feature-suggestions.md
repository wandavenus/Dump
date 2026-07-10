# Saran Fitur Baru (Offline / Non-Online)

Daftar ide fitur yang **belum ada** di app berdasarkan inventaris fitur saat ini (playback, library, lyrics, audio effects, theming, queue, notifikasi). Semua fitur di bawah murni lokal/offline — tidak termasuk fitur yang butuh koneksi internet/API eksternal.

## 1. Playlist & Organisasi Lagu
- **Playlist buatan sendiri (custom playlist)** — saat ini cuma ada smart list (Favorites, Recently Played, Most Played). Belum ada playlist manual yang bisa dibuat/dinamai/diedit user.
- **Import/Export playlist format `.m3u` / `.m3u8`** — biar playlist bisa dipindah dari/ke pemutar musik lain.
- **Tambah ke playlist langsung dari mini player / now playing** — shortcut cepat tanpa buka menu panjang.
- **Multi-select & batch actions** di daftar lagu (hapus dari playlist, tambah ke playlist lain, share file, dll) sekaligus banyak lagu.
- **Smart filter/sort lanjutan** — sort by ukuran file, bitrate, tanggal ditambahkan, durasi, format file (mp3/flac/dll).
- **Folder sebagai playlist otomatis** — treat folder tertentu sebagai playlist yang auto-update saat isi folder berubah.

## 2. Tag & Metadata Editor
- **Editor metadata built-in** (judul, artis, album, album art, nomor track, genre, tahun) — saat ini app hanya membaca metadata, belum bisa mengedit/menulis tag balik ke file.
- **Ganti/tempel artwork manual** per lagu/album dari galeri, kalau artwork bawaan tidak ada/salah.
- **Deteksi & gabungkan duplikat lagu** (berdasarkan judul+artis atau audio fingerprint) untuk bersih-bersih library.
- **Manajemen storage** — lihat lagu dengan ukuran file terbesar, cari file rusak/corrupt, hapus langsung dari app.

## 3. Playback & Listening Experience
- **Crossfade dengan durasi custom** yang bisa diatur user (slider detik), bukan cuma gapless/fade otomatis.
- **A-B repeat / loop segmen lagu** — ulang bagian tertentu dari lagu (misal buat latihan vokal/musik).
- **Bookmark posisi dalam track panjang** (podcast/audiobook/lagu panjang) supaya bisa lanjut dari titik terakhir, terpisah dari resume queue biasa.
- **Playback speed control** (0.5x–2x) tanpa mengubah pitch.
- **Pitch shift / key control** independen dari speed.
- **Volume normalization otomatis antar-lagu** (selain ReplayGain tag-based) — analisis loudness langsung dari file kalau tag tidak tersedia.
- **Custom gesture di mini player/now playing** (misal double-tap untuk like, swipe tertentu untuk skip 10s).

## 4. Sleep Timer & Automation Lanjutan
- **Sleep timer dengan fade-out volume** bertahap sebelum berhenti, bukan cuma stop mendadak.
- **Shake-to-shuffle / shake-to-skip** pakai sensor accelerometer.
- **Auto-pause saat headset dilepas dengan opsi resume otomatis saat dipasang lagi** (kalau belum granular).
- **Jadwal pemutaran (scheduler)** — misal alarm musik pagi dari playlist tertentu.

## 5. UI/UX & Aksesibilitas
- **Home screen widget** (Android widget) untuk kontrol playback tanpa buka app.
- **Mode mobil/driving mode** — tampilan tombol besar, minim teks, untuk dipakai saat mengemudi.
- **Lock screen lyrics** — tampilkan lirik berjalan di lock screen, bukan cuma di dalam app.
- **Kustomisasi tombol hardware/headset** (single/double/triple click untuk aksi berbeda).
- **Waveform seekbar** — progress bar berbentuk waveform audio, bukan garis polos.
- **Tema custom per-playlist/album** (opsional override warna tema selain dari album art extraction).

## 6. Statistik & Insight
- **Statistik mendengarkan personal** — total jam dengar per minggu/bulan, top genre, top artist, semacam "Music Wrapped" lokal.
- **Riwayat lengkap dengan timestamp** (bukan cuma "Recently Played" terbatas) yang bisa difilter per tanggal.

## 7. Backup & Manajemen Data
- **Backup & restore pengaturan app** (equalizer preset, tema, playlist, favorites) ke file lokal, untuk pindah device atau reset app tanpa kehilangan data.
- **Export daftar lagu/library ke file teks/CSV** untuk keperluan pribadi (misal katalog koleksi).

---
*Catatan: daftar ini fokus ke fitur yang bisa berjalan penuh offline. Fitur yang butuh API/internet (lyrics online, radio streaming, dll) sengaja tidak dimasukkan karena sudah ada atau di luar cakupan permintaan.*
