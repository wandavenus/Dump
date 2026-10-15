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
    version: '1.5.34',
    date: '15 Oktober 2026',
    changes: [
      'Tambah fitur AutoMix: pengurutan antrean DJ-style murni offline tanpa AI — memakai ekstraksi BPM (onset-autokorelasi), kunci Camelot (korelasi profil Krumhansl-Schmuckler), dan energi (loudness, brightness, densitas onset).',
      'Pengaturan AutoMix: profil (DJ / Harmonic / Energy), toleransi BPM, panjang crossfade dalam ketukan, variasi artis, dan filter harmonik di Pengaturan > Audio.',
      'Analisis library (BPM & kunci) dari Pengaturan > Audio; tombol AutoMix ada di menu overflow player untuk antrean yang sedang berputar.',
    ],
  ),

  _ChangelogEntry(
    version: '1.5.33',
    date: '10 Oktober 2026',
    changes: [
      'Fix mode shuffle agar tetap tersimpan dan tombol shuffle di full player tetap sesuai state-nya setelah playback dihentikan lewat tombol stop di notifikasi (termasuk saat app di-kill sistem).',
      'Fix shuffle yang bisa aktif kembali sendiri setelah dimatikan user ketika queue dibangun ulang.',
      'Fix state shuffle yang sempat tertimpa nilai lama saat crossfade dipulihkan.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.31',
    date: '3 Oktober 2026',
    changes: [
      'Fix log Sleep Timer yang muncul saat playback biasa.',
      'Optimasi Acoustic Engine: debounce input, setter lebih efisien, dan buffer lebih tahan terhadap NaN/Inf.',
      'Hapus fitur Up Next beserta pengaturan dan terjemahannya.',
      'Update dependency dan Flutter ke stable 3.47.6.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.30',
    date: '14 Agustus 2026',
    changes: [
      'Fix refresh artwork MediaSession saat active player berganti atau crossfade dibatalkan.',
      'Fix celah refresh artwork pada pembatalan crossfade berdasarkan hasil audit.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.29',
    date: '11 Agustus 2026',
    changes: [
      'Fix artwork notifikasi lama muncul saat skip lagu dengan cepat.',
      'Optimasi loading artwork dengan in-flight request per lagu.',
      'Fix refresh artwork MediaSession setelah crossfade.',
      'Fix fallback artwork album kompilasi agar memeriksa semua lagu.',
      'Optimasi teardown service dengan menghentikan executor artwork.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.28',
    date: '10 Agustus 2026',
    changes: [
      'Optimasi artwork notifikasi/lock-screen dengan cache album dan probe album kompilasi.',
      'Optimasi resolusi dan decoding artwork agar lebih tajam dan efisien.',
      'Fix artwork prewarm agar langsung tampil setelah lagu diputar.',
      'Optimasi prewarm artwork pada pergantian lagu non-crossfade.',
      'Fix skip next/prev terlalu cepat agar tidak memicu stutter.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.27',
    date: '10 Agustus 2026',
    changes: [
      'Fix artwork notifikasi/lock-screen MIUI yang zoom dan pecah dengan artwork MediaSession full-res.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.26',
    date: '10 Agustus 2026',
    changes: [
      'Bersihkan dead code getBytes() beserta cache bytes dari ArtworkRepository.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.25',
    date: '10 Agustus 2026',
    changes: [
      'Audit optimasi palette: pastikan tidak ada pembacaan disk artwork ganda.',
      'Optimasi getBytes() dengan dedup in-flight agar tidak ada pembacaan file ganda.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.24',
    date: '10 Agustus 2026',
    changes: [
      'Optimasi loading artwork saat scroll dengan pre-decode viewport dan jendela sekitar.',
      'Optimasi pre-decode dengan prioritas viewport dan request coalescing saat fling.',
      'Fix decode artwork ganda saat scroll.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.23',
    date: '10 Agustus 2026',
    changes: [
      'Fix batch write ReplayGain dengan dedup songId.',
      'Optimasi batch write ReplayGain dengan chunk 250 lagu dan 2 worker paralel.',
      'Fix batch write ReplayGain agar kegagalan non-channel tidak membatalkan batch lain.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.22',
    date: '10 Agustus 2026',
    changes: [
      'Optimasi batch write ReplayGain dengan 2 worker native paralel.',
      'Fix validasi hasil writeReplayGainBatch agar respons kosong/terpotong dianggap gagal.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.21',
    date: '10 Agustus 2026',
    changes: [
      'Optimasi write ReplayGain dengan satu native batch call untuk seluruh hasil scan.',
      'Optimasi penulisan ReplayGain dengan 2 worker paralel.',
      'Optimasi scan cache artwork dengan throttle LRU.',
      'Optimasi ekstraksi artwork dengan raw-copy PNG/WebP kecil tanpa decode-reencode.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.20',
    date: '10 Agustus 2026',
    changes: [
      'Optimasi load library dengan payload JSON tunggal dan parsing di isolate.',
      'Optimasi ReplayGain scan dengan reuse buffer PCM.',
      'Optimasi DSP soft clipper tanpa fungsi transcendental.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.19',
    date: '9 Agustus 2026',
    changes: [
      'Optimasi ekstraksi artwork JPEG kecil dengan raw-copy tanpa decode-reencode.',
      'Optimasi prefetch artwork dengan tambahan thread ekstraksi.',
      'Bersihkan dead code getArtwork yang tidak digunakan.',
      'Optimasi artwork notifikasi/lock-screen dengan cache persisten dan decode maksimal 512px.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.18',
    date: '9 Agustus 2026',
    changes: [
      'Optimasi loading artwork dengan prefetch saat scroll.',
      'Optimasi artwork lagu berikutnya dengan prefetch otomatis.',
      'Optimasi prefetch artwork secara paralel.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.17',
    date: '8 Agustus 2026',
    changes: [
      'Fix reliabilitas artwork dan hapus lagu dengan timeout fail-open.',
      'Hapus dependency cached_network_image dan rxdart yang tidak terpakai.',
      'Rapikan helper format total durasi Album dan Artist.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.16',
    date: '8 Agustus 2026',
    changes: [
      'Lokalisasi alur simpan QRIS untuk Bahasa Indonesia dan English.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.15',
    date: '8 Agustus 2026',
    changes: [
      'Update Media3 ke 1.11.0 stable.',
      'Optimasi memori dengan menghentikan parsing artwork bawaan file.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.14',
    date: '7 Agustus 2026',
    changes: ['Fix animasi highlight karaoke untuk teks Jepang dan CJK.'],
  ),
  _ChangelogEntry(
    version: '1.5.11',
    date: '5 Agustus 2026',
    changes: [
      'Optimasi animasi background player agar layer warna tetap stabil saat bercampur.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.10',
    date: '5 Agustus 2026',
    changes: [
      'Fix background kartu album Homepage agar memakai satu warna dominan artwork.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.9',
    date: '5 Agustus 2026',
    changes: [
      'Fix palette artwork agar warna warm seperti skin tone dan beige tetap muncul.',
      'Optimasi gradient kartu album agar mempertahankan navy dan warna pendukung artwork.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.8',
    date: '2 Agustus 2026',
    changes: [
      'Fix pembatalan crossfade saat pause, stop, atau perubahan durasi.',
      'Fix perubahan volume user agar diterapkan ke target fade terbaru.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.1',
    date: '29 Juli 2026',
    changes: ['Fix tap kartu artwork Favorit agar langsung memutar lagu.'],
  ),
  _ChangelogEntry(
    version: '1.5.0',
    date: '29 Juli 2026',
    changes: ['Redesign Favorit di Radio Page menjadi grid artwork 3×2.'],
  ),
  _ChangelogEntry(
    version: '1.4.9',
    date: '29 Juli 2026',
    changes: ['Hapus seksi Baru Dimainkan dan Paling Sering dari Radio Page.'],
  ),
  _ChangelogEntry(
    version: '1.4.8',
    date: '27 Juli 2026',
    changes: [
      'Fix 3 compile error yang mengganggu build.',
      'Optimasi Future fire-and-forget dengan unawaited() dan .ignore().',
      'Bersihkan import dart:async yang tidak terpakai.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.7',
    date: '27 Juli 2026',
    changes: ['Sederhanakan output analyzer menjadi error dan warning.'],
  ),
  _ChangelogEntry(
    version: '1.4.6',
    date: '27 Juli 2026',
    changes: [
      'Fix error analyzer yang memengaruhi build dan type safety.',
      'Perjelas penanganan operasi async background.',
      'Perketat parsing respons provider lirik.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.5',
    date: '27 Juli 2026',
    changes: [
      'Lengkapi lokalisasi metadata dan jumlah lagu di Library.',
      'Sinkronkan placeholder terjemahan Indonesia dengan generator localization.',
      'Fix compile error pada player dan halaman Log setelah migrasi lokalisasi.',
      'Fix preset Sleep Timer agar mengikuti bahasa aktif.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.4',
    date: '27 Juli 2026',
    changes: [
      'Lengkapi lokalisasi halaman Artist, Album, dan footer Settings.',
      'Tambah key l10n untuk durasi dan jumlah lagu.',
      'Fix More by Artist dan footer copyright agar mengikuti bahasa aktif.',
      'Fix versi yang tampil di halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.3',
    date: '27 Juli 2026',
    changes: [
      'Lengkapi terjemahan Indonesia dan English di seluruh fitur utama.',
      'Tambah format terjemahan untuk durasi, jumlah lagu, metadata artist, dan kontrol audio.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.2',
    date: '27 Juli 2026',
    changes: [
      'Tambah dukungan multibahasa Indonesia dan English.',
      'Fix pergantian bahasa UI tanpa restart app.',
      'Tambah pilihan bahasa di Pengaturan.',
      'Lengkapi lokalisasi navigasi, halaman Log, Equalizer, Sleep Timer, About, Bug Report, Library, Browse, dan Radio.',
      'Lokalisasi nama smart playlist.',
      'Fix versi yang tampil di halaman About.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.1',
    date: '26 Juli 2026',
    changes: [
      'Update flutter_cache_manager ke 3.4.2 untuk memperbaiki bug removeFile().',
      'Update synchronized ke 3.4.1+1 untuk kompatibilitas Dart 3.12.',
    ],
  ),
  _ChangelogEntry(
    version: '1.4.0',
    date: '24 Juli 2026',
    changes: [
      'Update engine palette dari Dart ke native Android androidx.palette.',
      'Optimasi kualitas dan konsistensi warna artwork.',
      'Hapus dependency palette_generator_plus.',
      'Fix lyrics sheet agar tidak masuk half mode saat swipe di area kontrol.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.9',
    date: '24 Juli 2026',
    changes: [
      'Optimasi performa Morph Player untuk target 60 FPS.',
      'Optimasi animasi drag dengan Positioned + Transform tanpa relayout tiap frame.',
      'Optimasi PlayerSheetController memakai Ticker vsync-driven.',
      'Optimasi artwork morph agar tidak re-decode saat transisi.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.8',
    date: '23 Juli 2026',
    changes: [
      'Fix stabilitas build APK di Replit dengan setup Flutter, Java, dan Android SDK.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.7',
    date: '21 Juli 2026',
    changes: ['Fix keterlambatan judul dan artis notifikasi saat crossfade.'],
  ),
  _ChangelogEntry(
    version: '1.3.6',
    date: '21 Juli 2026',
    changes: [
      'Fix artwork notifikasi saat crossfade dengan prewarm lebih awal.',
      'Fix duplikasi load artwork saat crossfade.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.5',
    date: '21 Juli 2026',
    changes: [
      'Fix artwork notifikasi dengan fallback ke ArtworkCacheManager.',
      'Fix blacklist artwork permanen dengan TTL retry 30 detik.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.4',
    date: '19 Juli 2026',
    changes: [
      'Optimasi performa native stereo dengan fast-path pada limiter dan compressor.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.3',
    date: '19 Juli 2026',
    changes: [
      'Fix crossfade prewarm agar intro lagu berikutnya tidak terlewati.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.2',
    date: '19 Juli 2026',
    changes: [
      'Fix activeQueueIndex agar UI dan notifikasi tidak salah saat crossfade.',
    ],
  ),
  _ChangelogEntry(
    version: '1.3.1',
    date: '19 Juli 2026',
    changes: ['Fix Repeat ONE agar crossfade tidak memutar lagu berikutnya.'],
  ),
  _ChangelogEntry(
    version: '1.3.0',
    date: '19 Juli 2026',
    changes: [
      'Fix animasi judul AppBar saat scroll agar smooth tanpa threshold diskrit.',
      'Optimasi rebuild AppBar agar berhenti setelah melewati rentang animasi.',
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
      'Refactor arsitektur Lyrics dengan satu LyricsCacheManager.',
      'Fix provider detection dengan flag isEmbedded typed.',
      'Optimasi 429 rate-limit handling melalui ProviderHttp.',
      'Rapikan parsing data Kuwo untuk null safety.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.8',
    date: '18 Juli 2026',
    changes: ['Fix Mini Player tidak muncul setelah Activity destroyed.'],
  ),
  _ChangelogEntry(
    version: '1.2.7',
    date: '18 Juli 2026',
    changes: [
      'Optimasi rebuild Player Sheet agar position tick tidak me-rebuild layout morph.',
      'Optimasi UnifiedMorphPlayer dengan pemisahan _PlaybackContent.',
      'Refactor player state untuk memisahkan playback dan progress.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.5',
    date: '18 Juli 2026',
    changes: [
      'Bersihkan assets gambar yang tidak digunakan beserta referensinya.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.4',
    date: '18 Juli 2026',
    changes: [
      'Bersihkan file dan widget mati.',
      'Rapikan radioStations dan penamaan file.',
      'Rapikan nama variabel fog_painter agar lebih deskriptif.',
      'Rapikan parameter setter ThemeController dari v menjadi enabled.',
      'Perbaiki KDoc PlaybackNotificationManager yang sudah stale.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.3',
    date: '18 Juli 2026',
    changes: ['Hapus fitur Skip Silence.'],
  ),
  _ChangelogEntry(
    version: '1.2.1',
    date: '17 Juli 2026',
    changes: [
      'Fix crash ReplayGain pada file audio corrupt/malformed.',
      'Fix data race nativeComputeAlbumLoudness.',
      'Fix nama app dari Apple Music menjadi Music.',
      'Fix Handler leak pada SleepTimerManager.',
      'Fix Thread leak pada NowPlayingOverlayActivity.',
      'Tambah stack protection pada stretch_native.',
      'Tambah error handling pada operasi async LyricsSettings.',
    ],
  ),
  _ChangelogEntry(
    version: '1.2.0',
    date: '15 Juli 2026',
    changes: [
      'Update engine Speed & Pitch dari Sonic ke Signalsmith Stretch native.',
      'Optimasi Speed & Pitch dengan processor terpisah per player dan fallback aman.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.9',
    date: '15 Juli 2026',
    changes: ['Optimasi ReplayGain processor dengan NEON kernel untuk ARM64.'],
  ),
  _ChangelogEntry(
    version: '1.1.8',
    date: '15 Juli 2026',
    changes: ['Optimasi Crossfeed processor dengan NEON kernel untuk ARM64.'],
  ),
  _ChangelogEntry(
    version: '1.1.7',
    date: '15 Juli 2026',
    changes: [
      'Optimasi Loudness Normalization dengan NEON kernel untuk ARM64.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.6',
    date: '15 Juli 2026',
    changes: [
      'Tambah ARM64 NEON kernels untuk gain dan biquad stereo.',
      'Optimasi Gain processor dengan NEON dan fallback scalar.',
    ],
  ),
  _ChangelogEntry(
    version: '1.1.5',
    date: '14 Juli 2026',
    changes: ['Tambah konten lengkap pada halaman Laporkan Bug.'],
  ),
  _ChangelogEntry(
    version: '1.0.4',
    date: '14 Juli 2026',
    changes: [
      'Pindahkan akses Changelog dari Settings ke halaman Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.3',
    date: '14 Juli 2026',
    changes: [
      'Tambah deskripsi app, link Catatan Pembaruan, dan sosial media di Tentang App.',
    ],
  ),
  _ChangelogEntry(
    version: '1.0.2',
    date: '14 Juli 2026',
    changes: ['Redesign halaman Tentang App menjadi minimalis.'],
  ),
  _ChangelogEntry(
    version: '0.0.1',
    date: '07 Mei 2026',
    changes: ['Initial Build'],
  ),
];
