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
    version: '1.0.0',
    date: '15 Juli 2026',
    changes: [
      'Crossfeed processor sekarang pakai NEON kernel juga: filter lowpass cross-path dan HF shelf compensation diproses L+R bareng lewat nar_biquad_stereo_neon di perangkat arm64, fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.0',
    date: '15 Juli 2026',
    changes: [
      'Loudness Normalization sekarang pakai NEON kernel juga: K-weighting stereo (L+R) diproses bareng lewat nar_biquad_stereo_neon di perangkat arm64, fallback scalar untuk build lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.0',
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
