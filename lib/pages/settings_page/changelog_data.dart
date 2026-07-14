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
    date: '14 Juli 2026',
    changes: [
      'Penambahan deskripsi app, link Catatan Pembaruan, dan sosmed (Instagram & Facebook) di halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.0',
    date: '14 Juli 2026',
    changes: [
      'Redesign halaman Tentang App menjadi tampilan minimalis.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.0',
    date: '14 Juli 2026',
    changes: [
      'Penambahan section Tentang di Pengaturan dengan 4 menu navigasi.',
      'Footer developer & copyright di bawah section Tentang.',
      'Divider tiap item Pengaturan diubah agar tidak full width.',
    ],
  ),
];
