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
      'Halaman "Tentang App" dirombak total: tampilan minimalis terpusat — nama app, versi, divider pendek, teks "Dibuat dengan dedikasi oleh Wndavenznchole", dan copyright di footer bawah.',
      'App bar dengan tombol back merah tetap ada; easter egg ketuk versi 5× untuk Mode Debug dipertahankan langsung pada teks versi.',
      'Widget _VersionTile lama dihapus dan logikanya disatukan ke dalam halaman.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.0',
    date: '14 Juli 2026',
    changes: [
      'Menambahkan teks footer abu-abu ("Made by Wndavenznchole" + copyright tahun berjalan) di bawah menu "Tentang App" pada section Tentang, tanpa divider putih.',
      'Section "Tentang" di halaman Pengaturan dirombak menjadi 4 menu navigasi: Changelog, Laporkan Bug, Dukungan, dan Tentang App.',
      'Info aplikasi (nama, developer, versi) dipindahkan ke halaman "Tentang App" tersendiri.',
      'Divider pada tiap item di halaman Pengaturan diubah agar tidak full width — kini simetris kiri-kanan (indent 16, endIndent 16) mengikuti gaya divider di bawah judul besar halaman.',
    ],
  ),
];
