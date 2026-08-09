part of '../settings_page.dart';

// ─── Changelog data ─────────────────────────────────────────────────────────
//
// Setiap kali ada perubahan pada app, tambahkan satu _ChangelogEntry baru di
// urutan PALING ATAS (terbaru dulu) — sertakan versi app (dari pubspec.yaml)
// dan tanggal pengerjaan. Ini adalah catatan wajib, bukan opsional.

class _ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  const _ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

const List<_ChangelogEntry> _changelogEntries = [
  _ChangelogEntry(
    version: '1.5.20',
    date: '10 Agustus 2026',
    changes: [
      'Percepat load library: payload getSongs dikirim native sebagai satu string JSON (bukan ribuan Map lewat codec) dan parsing + encode cache dipindah ke isolate (compute) — refresh library besar tidak lagi nge-jank UI thread.',
      'ReplayGain scan: buffer PCM MediaCodec di-reuse (grow-only) — tidak ada alokasi ShortArray per chunk selama decode.',
      'DSP soft clipper: ganti tanhf() dengan aproksimasi rasional cepat (C¹, bounded, error <2.5%) — jalur clip tanpa transcendental.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.19',
    date: '9 Agustus 2026',
    changes: [
      'Percepat ekstraksi artwork native: JPEG kecil disalin mentah ke cache tanpa decode-reencode (kualitas asli, ekstraksi hampir instan).',
      'Tambah 1 thread ekstraksi artwork (2 → 3) agar batch prefetch lebih cepat selesai.',
      'Bersihkan kode mati: hapus jalur getArtwork (bytes) yang tidak pernah dipanggil Flutter.',
      'FallbackBitmapLoader (artwork notifikasi/lock-screen): reuse cache artwork persisten + decode dibatasi 512px agar tidak pernah decode full-size.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.18',
    date: '9 Agustus 2026',
    changes: [
      'Percepat loading artwork: prefetch otomatis saat scroll list Lagu agar sampul siap sebelum terlihat.',
      'Percepat loading artwork: prefetch sampul 3 lagu berikutnya saat ganti lagu.',
      'Percepat prefetch artwork itu sendiri (paralel 2) untuk list lagu besar.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.17',
    date: '8 Agustus 2026',
    changes: [
      'Perkuat reliabilitas: artwork & hapus lagu kini punya timeout fail-open agar tidak menggantung selamanya.',
      'Bersihkan dependency: hapus cached_network_image dan rxdart dari pubspec (tidak terpakai langsung).',
      'Rapikan kode: satukan format total durasi halaman Album & Artist jadi satu helper.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.16',
    date: '8 Agustus 2026',
    changes: [
      'Lokalisasi lengkap alur simpan QRIS (dialog + snackbar) ke EN/ID.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.15',
    date: '8 Agustus 2026',
    changes: [
      'Perbarui Media3 ke 1.11.0 stable dan pindahkan BitmapLoader ke androidx.media3.common.util.',
      'Hentikan parsing artwork bawaan file (MP3/MP4/FLAC) untuk hemat memori — artwork tetap ditampilkan lewat cache internal.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.14',
    date: '7 Agustus 2026',
    changes: ['Perbaiki animasi highlight karaoke untuk teks Jepang dan CJK.'],
  ),
  _ChangelogEntry(
    version: '1.5.13',
    date: '6 Agustus 2026',
    changes: ['Seimbangkan jarak kiri dan kanan pada tampilan lirik.'],
  ),
  _ChangelogEntry(
    version: '1.5.12',
    date: '6 Agustus 2026',
    changes: [
      'Perbaiki highlight lirik Arab dan campuran Arab-Latin agar arah gerak serta posisi teks lebih akurat.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.11',
    date: '5 Agustus 2026',
    changes: [
      'Ubah animasi background player agar warna tetap di layer masing-masing, lalu berubah dan saling bercampur tanpa bentuk kabut atau cairan yang berpindah.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.10',
    date: '5 Agustus 2026',
    changes: [
      'Kembalikan background kartu album di Homepage ke satu warna dominan dari artwork.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.9',
    date: '5 Agustus 2026',
    changes: [
      'Perbaiki palette artwork agar warna warm seperti skin tone atau beige tidak hilang saat artwork hanya punya dua keluarga warna utama.',
      'Pertahankan navy sebagai warna utama dan buat gradient kartu album tetap membawa warna pendukung dari artwork.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.8',
    date: '2 Agustus 2026',
    changes: [
      'Perbaiki pembatalan crossfade saat pause, stop, atau perubahan durasi agar player tidak tertinggal dengan queue satu lagu.',
      'Perubahan volume user saat crossfade berlangsung kini diterapkan ke target fade terbaru.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.1',
    date: '29 Juli 2026',
    changes: [
      'Tap kartu artwork di grid Favorit langsung memutar lagu tanpa pindah halaman.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.0',
    date: '29 Juli 2026',
    changes: [
      'Ubah tampilan seksi Favorit di Radio Page dari 1 kartu banner besar ke grid 3×2 kartu artwork kecil.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.9',
    date: '29 Juli 2026',
    changes: [
      'Hapus seksi "Baru Dimainkan" dan "Paling Sering" beserta kartu dan banner-nya dari Radio Page.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.8',
    date: '27 Juli 2026',
    changes: [
      'Hapus 3 compile error (void result, syntax token, undefined function).',
      'Bungkus semua Future fire-and-forget dengan unawaited() di ~30 file.',
      'Ganti pola Future discarded di dispose() pakai .ignore() yang lebih aman.',
      'Hapus import dart:async yang tidak terpakai.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.7',
    date: '27 Juli 2026',
    changes: [
      'Sederhanakan output analyzer agar hanya menampilkan error dan warning.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.6',
    date: '27 Juli 2026',
    changes: [
      'Perbaiki error analyzer yang bisa mengganggu build dan type safety.',
      'Perjelas penanganan operasi async yang sengaja berjalan di background.',
      'Perketat parsing respons provider lirik agar lebih aman saat format data berubah.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.5',
    date: '27 Juli 2026',
    changes: [
      'Lengkapi integrasi lokalisasi pada label metadata file, debug, dan jumlah lagu di Library.',
      'Sinkronkan metadata placeholder terjemahan Indonesia agar generator localization konsisten.',
      'Perbaiki error compile pada beberapa bagian player dan halaman Log setelah migrasi lokalisasi.',
      'Pastikan preset Sleep Timer selalu mengikuti bahasa aktif saat ditampilkan.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.4',
    date: '27 Juli 2026',
    changes: [
      'Lokalisasi penuh: ganti semua string hardcoded di halaman artis, album, dan footer Settings dengan kunci terjemahan.',
      'Tambah format durasi (jam/menit) dan jumlah lagu+durasi sebagai kunci l10n baru di EN dan ID.',
      'Perbaiki "More by Artist" dan footer copyright di halaman album untuk mengikuti bahasa aktif.',
      'Perbaiki versi yang tampil di halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.3',
    date: '27 Juli 2026',
    changes: [
      'Lengkapi terjemahan Indonesia dan English untuk player, lirik, Home, detail artis/album, playlist, Equalizer, Log, dan status audio.',
      'Tambahkan format terjemahan untuk durasi, jumlah lagu, metadata artis, dan nilai kontrol audio.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.2',
    date: '27 Juli 2026',
    changes: [
      'Tambah dukungan multibahasa penuh (Bahasa Indonesia & English).',
      'Semua teks UI kini bisa berganti bahasa secara instan tanpa restart app.',
      'Pilihan bahasa tersedia di Pengaturan → Bahasa (Indonesia / English / Ikuti Sistem).',
      'Perbaiki label navigasi bawah, halaman Log, Equalizer, Sleep Timer, About, Bug Report, Library, Browse, dan Radio agar ikut terjemahan aktif.',
      'Perbaiki nama smart playlist (Favorit, Baru Dimainkan, Paling Sering) agar terlokalisasi.',
      'Perbaiki versi yang ditampilkan di halaman About (1.1.5 → 1.4.2).',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.1',
    date: '26 Juli 2026',
    changes: [
      'Upgrade flutter_cache_manager 3.4.1 → 3.4.2: fix bug removeFile() yang menghapus dari path salah (potensi storage leak di artwork cache).',
      'Upgrade synchronized 3.4.1 → 3.4.1+1: kompatibilitas Dart 3.12.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.0',
    date: '24 Juli 2026',
    changes: [
      'Ganti engine ekstraksi warna album dari palette_generator_plus (Dart) ke engine native Android (androidx.palette) dengan algoritma pemilihan warna perceptual.',
      'Warna palette kini lebih vibrant, lebih beragam, dan lebih konsisten untuk semua jenis artwork.',
      'Hapus dependency palette_generator_plus dari pubspec.',
      'Hilangkan pemicu lyrics sheet ke half mode saat user swipe di area tombol kontrol.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.9',
    date: '24 Juli 2026',
    changes: [
      'Optimasi 60 FPS Morph Player: hilangkan semua implicit animation (AnimatedPositioned, AnimatedContainer, AnimatedOpacity) dari jalur drag mini→full player.',
      'Album cover kini pakai Positioned + Transform (translate+scale) agar tidak ada relayout setiap frame saat drag.',
      'PlayerSheetController: ganti Timer.periodic dengan Ticker vsync-driven (SchedulerBinding) agar animasi sync dengan refresh rate display.',
      'Artwork selalu decode di resolusi besar selama morph — tidak ada re-decode saat transisi.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.8',
    date: '23 Juli 2026',
    changes: [
      'Perbaikan proses build APK di Replit agar setup Flutter, Java, dan Android SDK berjalan stabil.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.7',
    date: '21 Juli 2026',
    changes: [
      'Fix judul & artis notifikasi terlambat berganti saat crossfade: MediaSession kini diperbarui secara sinkron saat pergantian player, sehingga MIUI media widget dan lock screen langsung menampilkan lagu baru.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.6',
    date: '21 Juli 2026',
    changes: [
      'Fix artwork notifikasi saat crossfade: artwork tidak lagi kosong/terlambat muncul di notifikasi saat lagu berganti — artwork dimuat 1500 ms lebih awal di window prewarm sebelum fade dimulai.',
      'Fix duplikasi pemuatan artwork: 3 panggilan loadBitmap() beruntun dalam ~1 ms saat crossfade mulai kini diciutkan menjadi 1 — latency artwork berkurang hingga 3× di worst case.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.5',
    date: '21 Juli 2026',
    changes: [
      'Fix artwork notifikasi: notifikasi kini pakai pipeline yang sama dengan Full Player — fallback ke ArtworkCacheManager (embedded art + disk cache) jika MediaStore album art URI gagal.',
      'Fix blacklist artwork permanen: no-artwork cache sekarang TTL 30 detik, bukan permanen — lagu yang gagal saat cold start otomatis di-retry tanpa perlu restart app.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.4',
    date: '19 Juli 2026',
    changes: [
      'Phase 1 native perf: limiter & compressor stereo fast-path — unroll inner channel loops (delay write, peak detect, output multiply) untuk eliminasi loop overhead di path stereo.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.3',
    date: '19 Juli 2026',
    changes: [
      'Fix crossfade prewarm: intro lagu berikutnya tidak lagi terskip ~1 detik — prewarm tidak lagi memanggil play() yang membuat posisi maju diam-diam; standby cukup di-prepare() saja, play() dipanggil oleh beginCrossfade() dari posisi 0.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.2',
    date: '19 Juli 2026',
    changes: [
      'Fix DP-1: activeQueueIndex sekarang diperbarui sebelum standby.prepare()/play() — UI dan notifikasi tidak lagi menampilkan lagu yang salah saat crossfade dimulai.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.1',
    date: '19 Juli 2026',
    changes: [
      'Fix bug Repeat ONE + Crossfade memutar lagu berikutnya — crossfade sekarang tidak aktif saat Repeat ONE, biarkan ExoPlayer loop secara native.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.0',
    date: '19 Juli 2026',
    changes: [
      'Fix animasi judul AppBar yang terlihat "stepped" saat scroll — notifier sekarang diupdate setiap sub-pixel di rentang animasi (0–140px), tanpa threshold diskrit.',
      'Rebuild AppBar otomatis berhenti saat scroll melewati 140px (posisi visual sudah konstan) — tidak ada rebuild sia-sia di luar rentang animasi.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.9+2',
    date: '18 Juli 2026',
    changes: [
      'Phase 8D: shader background berhenti saat player collapsed — hemat GPU tiap frame.',
      'Pre-compute 9 lerped color floats di FogPainter; paint() tidak ada aritmatika.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.9',
    date: '18 Juli 2026',
    changes: [
      'Phase 8C: refactor arsitektur Lyrics — hapus dual cache (satu sumber kebenaran via LyricsCacheManager).',
      'Ganti string matching providerName.contains("tag") dengan flag isEmbedded typed di LyricsProviderResult.',
      'Pusatkan 429 rate-limit handling ke ProviderHttp — hapus duplikasi per-provider.',
      'Kuwo provider: ekstrak akses data["data"] sekali untuk null safety yang lebih jelas.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.8',
    date: '18 Juli 2026',
    changes: [
      'Regression fix: Mini Player tidak muncul saat app dibuka kembali setelah Activity destroyed — _entryAnim sekarang di-jump ke 1.0 di initState() bila lagu sudah aktif.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.7',
    date: '18 Juli 2026',
    changes: [
      'Phase 8B: refactor rebuild scope Player Sheet — position tick (~100ms) tidak lagi rebuild layout morph.',
      'Ekstrak _PlaybackContent widget di UnifiedMorphPlayer — hanya PlayerContent yang rebuild saat posisi berubah.',
      'Refactor player_sheet/state.dart — pisah VLB playbackState dari chain progress VLB.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.5',
    date: '18 Juli 2026',
    changes: [
      'Hapus assets/1.jpg, assets/2.jpg, assets/4.jpg (tidak dipakai) dan bersihkan referensi di browse_banners.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.4',
    date: '18 Juli 2026',
    changes: [
      'Hapus file dan widget mati (chip, sleep_timer, lyrics, lyrics_rows, notif_icon dari settings; FutureLocalSongCarousel).',
      'Bersihkan radioStations: type eksplisit, rename file webViewContainer → web_view_container.',
      'Rename variabel fog_painter dari kode kriptonim ke nama deskriptif (_old0r/_cur0r dll).',
      'Rename parameter v → enabled di semua setter ThemeController.',
      'Perbaiki KDoc stale PlaybackNotificationManager (hapus referensi MediaKitPlaybackService).',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.3',
    date: '18 Juli 2026',
    changes: ['Hapus fitur Skip Silence.'],
  ),
  _ChangelogEntry(
    version: '1.2.2',
    date: '18 Juli 2026',
    changes: [
      'Perbaiki metadata/artwork lagu B yang delay muncul saat crossfade — sekarang langsung update di awal fade, bukan menunggu volume 1.0.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.1',
    date: '17 Juli 2026',
    changes: [
      'Perbaiki crash saat scan ReplayGain pada file audio corrupt/malformed (MediaFormat.getInteger NPE).',
      'Perbaiki data race di nativeComputeAlbumLoudness: mutex sekarang dijaga sampai komputasi libebur128 selesai.',
      'Perbaiki label app "Apple Music" → "Music" (sudah diganti ke nama yang benar di strings.xml dan AndroidManifest).',
      'Perbaiki Handler runnable leak di SleepTimerManager: tambah release() yang dipanggil dari onDestroy() Service.',
      'Perbaiki Thread leak di NowPlayingOverlayActivity: metadata thread sekarang di-interrupt saat Activity destroyed.',
      'Tambah -fstack-protector-strong ke compile flags stretch_native (keamanan stack buffer).',
      'Tambah error handling ke unawaited LyricsSettings.flush(), syncFromNative(), dan writeEqBand() agar error tidak hilang diam-diam.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.0',
    date: '15 Juli 2026',
    changes: [
      'Engine Speed & Pitch diganti total: dari Sonic (bawaan Media3/ExoPlayer) ke Signalsmith Stretch — library time-stretch/pitch-shift native (C++) kualitas tinggi, jauh lebih bersih/tidak "robotic" terutama di speed/pitch ekstrem.',
      'Speed & pitch sekarang diproses di processor terpisah per player (mendukung crossfade tanpa konflik state), dengan fallback aman: kalau native library gagal dimuat, audio tetap main normal di 1.0x tanpa crash.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.9',
    date: '15 Juli 2026',
    changes: [
      'ReplayGain processor sekarang pakai NEON kernel juga (reuse kernel yang sama dengan gain processor): perkalian gain per-sample lebih cepat di perangkat arm64, fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.8',
    date: '15 Juli 2026',
    changes: [
      'Crossfeed processor sekarang pakai NEON kernel juga: filter lowpass cross-path dan HF shelf compensation diproses L+R bareng lewat nar_biquad_stereo_neon di perangkat arm64, fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.7',
    date: '15 Juli 2026',
    changes: [
      'Loudness Normalization sekarang pakai NEON kernel juga: K-weighting stereo (L+R) diproses bareng lewat nar_biquad_stereo_neon di perangkat arm64, fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.6',
    date: '15 Juli 2026',
    changes: [
      'Tambah ARM64 NEON Assembly kernels: nar_gain_apply_neon (16 sample/iterasi via fmul v.4s) dan nar_biquad_stereo_neon (L+R biquad paralel via 2-lane NEON).',
      'Gain processor sekarang pakai NEON kernel di perangkat arm64 (termasuk Snapdragon 730), fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.5',
    date: '14 Juli 2026',
    changes: [
      'Halaman Laporkan Bug diisi konten: teks penjelasan, link Gmail merah, dan referensi ke halaman Tentang.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.4',
    date: '14 Juli 2026',
    changes: [
      'Tombol Changelog dihapus dari halaman Pengaturan, akses hanya lewat halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.3',
    date: '14 Juli 2026',
    changes: [
      'Penambahan deskripsi app, link Catatan Pembaruan, dan sosmed (Instagram & Facebook) di halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.2',
    date: '14 Juli 2026',
    changes: ['Redesign halaman Tentang App menjadi tampilan minimalis.'],
  ),
  _ChangelogEntry(
    version: '1.0.1',
    date: '14 Juli 2026',
    changes: [
      'Penambahan section Tentang di Pengaturan dengan 4 menu navigasi.',
      'Footer developer & copyright di bawah section Tentang.',
      'Divider tiap item Pengaturan diubah agar tidak full width.',
    ],
  ),
  _ChangelogEntry(
    version: '0.0.1',
    date: '07 Mei 2026',
    changes: ['Initial Build'],
  ),
];
