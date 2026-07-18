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
    changes: [
      'Hapus fitur Skip Silence.',
    ],
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
    changes: [
      'Redesign halaman Tentang App menjadi tampilan minimalis.',
    ],
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
    changes: [
      'Initial Build',
    ],
  ),
];
