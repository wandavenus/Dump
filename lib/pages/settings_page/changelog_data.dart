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
    version: '1.5.64',
    date: '30 Oktober 2026',
    changes: [
      'Perbaikan lint pada inisialisasi Sentry tanpa mengubah perilaku pelaporan error.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.63',
    date: '30 Oktober 2026',
    changes: [
      'Integrasi Sentry Flutter untuk menangkap error Flutter/Dart dan crash native Android (Java/Kotlin/C/C++); DSN dibaca dari --dart-define, pengumpulan PII dan performance tracing tidak diaktifkan.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.62',
    date: '30 Oktober 2026',
    changes: [
      'AutoMix: analisis trek Android kini memakai satu sesi decode streaming — head dan middle ditangkap saat audio lewat, tail disimpan di ring buffer, jadi satu trek tidak lagi membuka decoder 2–4 kali; jalur per-window lama tetap menjadi fallback untuk bridge native lama.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.61',
    date: '30 Oktober 2026',
    changes: [
      'AutoMix: pemilihan tempo offline memakai ODF pita ketukan (low + 0,55×mid) dengan fallback envelope lebar; ODF full-band membaca hi-hat/ghost note sebagai ketukan, sehingga tiga lagu nyata yang semula 200/175,5/142 BPM kini terbaca 101/117/142 BPM (pembanding aubio 109,5/119,4/140,7).',
      'AutoMix: gate frasa turun ke keyakinan 0,35 (sama dengan grid Dart) dan bar 2 ketukan butuh margin 0,20, sehingga waltz 3/4 tetap terdeteksi dan lagu 4/4 tidak salah dilabeli meter 2.',
      'AutoMix: house four-on-the-floor datar kini mendapat downbeat bar dari perubahan akor per bar (fase 7 ms dari bar sebenarnya pada 120/124 BPM) meski tidak ada kontras aksen; meter tetap tidak dipublikasikan bila bukti aksen lemah.',
      'AutoMix: deteksi batas section men-de-trend novelty chroma terhadap laju perubahan akor lokal, sehingga progresi akor tiap bar tidak lagi menutupi batas verse→chorus 32 detik (kini 32000 ms, confidence 1,00).',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.60',
    date: '30 Oktober 2026',
    changes: [
      'AutoMix: meter 2 ketukan/bar kini didukung untuk 6/8 pada pulsa dotted-quarter; analyzer dan live tracker memilih bar 1,5 detik alih-alih 3 detik, dan grid frasa/fade memakai 8/4/2 ketukan.',
      'AutoMix: semua konsumen meter memvalidasi himpunan {2, 3, 4, 6} secara eksplisit, sehingga nilai 5 yang tidak pernah dipublikasikan hipotesis tidak lagi lolos sebagai meter yang sah.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.59',
    date: '30 Oktober 2026',
    changes: [
      'AutoMix: pemilihan tempo analyzer offline kini mengutamakan coverage onset, bukan puncak autokorelasi; four-on-the-floor 120 BPM dengan snare di ketukan 2/4 tidak lagi terbaca 60 BPM, dan breakbeat 174 BPM tidak lagi terbaca 87 BPM.',
      'AutoMix: jika minimal tiga dari empat quarter lagu sepakat pada satu level tempo, analyzer memakai konsensus itu; lagu dengan intro sparse 32 detik lalu chorus penuh tidak lagi dipentalkan setengah tempo (60 → 120 BPM).',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.58',
    date: '30 Oktober 2026',
    changes: [
      'AutoMix: live tracker kini menguji semua level metrikal (1x, 1/2x, 2x, 2/3x, 3/2x, 1/3x, 3x) sehingga lagu 90, 135, 160, 174, dan 180 BPM tidak lagi terkunci di 2/3x atau 1/2x tempo; confidence mengikuti margin antar-hipotesis.',
      'AutoMix: meter 3/4 dan 6/8 dideteksi di analyzer offline maupun live, dipakai untuk grid frasa, snap fade, dan phrase lock; meter hanya dipublikasikan jika menang di dua jendela riwayat dan didukung kenaikan low-band share, sehingga materi four-on-the-floor datar tidak lagi mengarang downbeat.',
      'AutoMix: analyzer mempublikasikan batas seksi track-level dari perubahan chroma 2 detik; jika batas itu jatuh 30-65 detik sebelum akhir lagu, early handover dimulai tepat di awal seksi terakhir, bukan di titik acak.',
      'AutoMix: akor dengan keyakinan rendah di tengah perubahan harmoni kini dijembatani hangover yang meluruh, jadi skor harmoni tidak lagi melihat celah 0.00 pada transisi yang sebenarnya selaras.',
      'AutoMix: pengulangan artis kini hanya diatur oleh artist cooldown (variety dihapus dari skor, bobotnya dibagi ke tempo/key/energi); crash potensial pada lookahead planner native diperbaiki, dan cache analisis dinaikkan ke skema v20.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.57',
    date: '29 Oktober 2026',
    changes: [
      'Decoder Opus dihapus dari build FFmpeg lokal karena perangkat sudah punya decoder Opus MediaCodec/CCodec bawaan; Opus kini didekode lewat jalur platform dan FFmpeg hanya membawa codec yang tidak tersedia di Android (ALAC, DTS/DTS-HD, TrueHD/MLP, Vorbis).',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.56',
    date: '29 Oktober 2026',
    changes: [
      'Pure Playback (single player tanpa DSP) kini mengaktifkan hardware audio offload Media3 saat perangkat dan format mendukung, sehingga decoding berjalan di DSP dan konsumsi baterai berkurang; format yang tidak didukung tetap jatuh ke PCM biasa.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.55',
    date: '28 Oktober 2026',
    changes: [
      'AutoMix: tempo kini ditentukan lewat uji hipotesis metrikal (bukan prior BPM), sehingga lagu 60–200 BPM tidak lagi salah oktaf 2x/0.5x/0.67x; beat phase tetap terdeteksi meski ada hi-hat off-beat.',
      'AutoMix: key detection menolak noise dan material tanpa harmoni, mengoreksi detune hingga ±50 sen, dan menurunkan confidence saat mayor/minor relatif ambigu; pergeseran pitch hanya aktif pada key yang benar-benar yakin.',
      'AutoMix: bar/frasa memakai bukti perubahan harmoni selain aksen energi, fade dikunci ke grid setengah-beat dan tidak lagi memanjang akibat phrase snap, serta biaya energi tidak lagi jenuh di 1.0.',
      'AutoMix: grid offline diprioritaskan saat berbeda dari live tracker, analisis lagu 241–300 detik menambah jendela tengah, dan cache analisis dinaikkan ke skema v19.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.54',
    date: '28 Oktober 2026',
    changes: [
      'Samakan ukuran emblem explicit di baris Music List, Library, Playlist, dan Search tanpa mengubah ukuran judul lagu.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.53',
    date: '27 Oktober 2026',
    changes: [
      'Perbaiki layout judul lagu agar emblem [E] tidak mengubah tampilan lagu non-explicit; metadata di header mini player kini dimuat saat benar-benar ditampilkan.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.52',
    date: '27 Oktober 2026',
    changes: [
      'Deteksi tag ITUNESADVISORY dari metadata audio dan tampilkan emblem [E] di samping judul lagu eksplisit.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.51',
    date: '27 Oktober 2026',
    changes: [
      'Gaya navbar Glass selebar layar dihapus; gaya Default dan Floating Pill tetap tersedia.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.50',
    date: '27 Oktober 2026',
    changes: [
      'Transisi collapse Floating Pill dipoles: circle kiri, pill mini player, dan circle Search mengecil hingga 95%; artwork dan judul bergeser 8 px ke kanan saat dock compact.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.49',
    date: '27 Oktober 2026',
    changes: [
      'Navbar pill dan mini player kini bergerak sebagai satu dock mengikuti scroll di seluruh halaman; item navbar menyusut menjadi ikon aktif sementara mini player menyatu di tengah, dengan gerakan dua arah yang mengikuti scroll.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.48',
    date: '25 Oktober 2026',
    changes: [
      'Deteksi fase beat dan frasa AutoMix kini memakai timestamp frame spectral-flux yang benar (titik tengah jendela + setengah hop), sehingga grid beat tidak lagi lebih awal 60-90 ms di semua sample rate.',
      'Deteksi awal frasa (4 bar) kini dinilai dari rata-rata energi per interval beat pada grid fraksional: aksen frasa yang nyata terdeteksi di 90-140 BPM, dan bar yang identik tidak lagi menghasilkan fase frasa palsu.',
      'Grid beat kepala lagu tidak lagi dipakai bila tempo ukirannya adalah oktaf lebih cepat dari tempo lagu, agar referensi fase tidak jatuh di offbeat.',
      'Envelope native fade kini menerapkan outgoing trim secara simetris, identik dengan fallback Kotlin AutomixGainEnvelope.',
      'Cache analisis naik ke skema v18; lagu yang pernah dianalisis akan dianalisis ulang dengan timestamp cue yang diperbaiki.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.44',
    date: '24 Oktober 2026',
    changes: [
      'AutoMix kini benar-benar menguras output PCM sampai decoder mengirim EOS; tail parsial tidak lagi dianggap sebagai analisis ekor lengkap.',
      'Jalur tone JNI AutoMix sekarang fail-open terhadap native library lama atau simbol yang tidak cocok: setelah linkage error, efek tone dilewati dan playback tetap transparan.',
      'Boundary native AutoMix kini hanya menerima dua target deck aktif; settings AutoMix yang rusak atau ekstrem kembali ke nilai aman sebelum masuk planner native.',
      'Scan library manual tidak lagi berjalan bersamaan dengan idle sweep AutoMix, sehingga decoder dan progress analisis tidak diperebutkan dua pekerjaan.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.43',
    date: '24 Oktober 2026',
    changes: [
      'Decoder FFmpeg kini dibangun lokal sebagai JNI (libffmpegJNI.so, FFmpeg 8.1.3, LGPL) dan tidak lagi memakai AAR Jellyfin GPL; dukungan ALAC, DTS/DTS-HD, TrueHD, Vorbis, dan Opus tetap sama.',
      'Build Android mengompilasi FFmpeg arm64-v8a otomatis saat pertama kali dibutuhkan; bila native library gagal dimuat, playback tetap fallback ke decoder MediaCodec platform.',
      'Perbaikan build: LogService.warn kini menerima stackTrace opsional seperti LogService.error, sehingga pemanggil logging dapat menyertakan jejak error.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.42',
    date: '23 Oktober 2026',
    changes: [
      'Audit logging: pesan log kini meredaksi path dan URI, kategori dinormalisasi, dan buffer menyimpan warning/error lebih lama.',
      'Log viewer kembali memperbarui live tail setelah buffer penuh; error Flutter dan Dart tetap dilaporkan walau logging dimatikan.',
      'Call site Dart, Kotlin, dan native dirapikan agar log verbose tidak membanjiri diagnostik dan tidak memuat judul lagu atau path pribadi.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.41',
    date: '22 Oktober 2026',
    changes: [
      'Semua jalur debugPrint aplikasi kini mengikuti toggle logging; log error registrasi plugin Android juga digate dengan preferensi yang sama.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.40',
    date: '22 Oktober 2026',
    changes: [
      'Saat logging dinonaktifkan, log aplikasi, diagnostik native, dan pengiriman log ke viewer dihentikan untuk mengurangi pekerjaan tambahan saat pemutaran.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.39',
    date: '16 Oktober 2026',
    changes: [
      'Optimasi blur artwork Now Playing dengan cache memori terbatas agar hasil blur dipakai ulang saat animasi player.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.38',
    date: '16 Oktober 2026',
    changes: [
      'Bass swap dan filter ekor AutoMix kini diproses di native C; stereo ARM64 memakai NEON, sementara konfigurasi kanal lain tetap memakai jalur C.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.38',
    date: '15 Oktober 2026',
    changes: [
      'AutoMix menyusun SELURUH antrean sekali di awal, bukan 25 lagu per transisi: urutan yang kamu dengar sudah diputuskan sekali, dan saat lagu berganti transisinya tinggal dipakai (tidak ada perhitungan ulang di tengah lagu).',
      'Beat-phase resync saat overlap: dua deck tidak lagi dibiarkan melenceng sendiri-sendiri — deck masuk dirapikan temponya (maksimal 0,6 %, tanpa mengubah pitch) selama fade agar ketukan tetap nyambung sampai selesai.',
      'Transisi kini pintar memilih: pasangan lagu yang temponya berdekatan baru ditarik biar ketukannya ketemu; kalau beda lagu terlalu jauh (lebih dari 6 %), AutoMix tidak memaksakan dan memakai crossfade halus biasa — jadi tidak ada suara "melengking/menggeser".',
      'Efek ekor halus: lagu yang keluar meredupkan nada tingginya bertahap (maksimal −12 dB) di paruh akhir fade, sehingga perpindahan terdengar lembut dan disengaja.',
      'Analisis seluruh library jalan sendiri di sela-sela pemutaran (beberapa lagu per sesi, jeda antar lagu) dan otomatis berhenti kalau baterai tidak dicas dan sudah di bawah 30 %, atau kalau HP kepanasan — jadi HP tidak lemot dan baterai aman.',
      'Analisis tersimpan tidak lagi kehilangan data struktur dan beat grid ekor lagu saat dibaca ulang (fase & panjang fade jadi konsisten).',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.37',
    date: '15 Oktober 2026',
    changes: [
      'Analisis AutoMix kini mencakup seluruh lagu: file dipotong menjadi jendela kepala/tengah/ekor, jadi lagu di atas 5 menit (dan outro-nya) ikut terukur — bukan cuma 300 detik pertama.',
      'Sadar struktur lagu: energi jendela pertama/terakhir dipakai untuk memilih panjang fade dan kurva perpindahan tiap transisi (outro padat = fade lebih cepat, outro sepi = fade lebih panjang dan halus).',
      'Beat grid transisi memakai tempo & fase di EKOR lagu yang keluar — titik fade sesungguhnya — bukan estimasi dari awal file.',
      'Level antar-deck disamakan saat overlap: deck yang lebih keras diredam (maksimal 6 dB, tidak pernah booster) lalu diredam-dilepas di akhir fade supaya tidak ada lonjakan level.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.36',
    date: '15 Oktober 2026',
    changes: [
      'AutoMix kini menganalisis sendiri di latar: BPM, kunci, dan fase ketukan lagu berikutnya diekstrak saat lagu berjalan — tanpa tombol "Analisis library", dan hasilnya tersimpan permanen per file.',
      'Tempo matching per deck, penyelarasan ketukan saat crossfade, dan bass hand-off jadi benar-benar aktif karena data analisis sudah tersedia sebelum transisi terjadi.',
      'Perencanaan antrean dibatasi ke 25 lagu berikutnya (urutan sisanya tidak diubah), dengan percobaan ulang terbatas ketika reorder ditolak di tengah crossfade.',
    ],
  ),
  _ChangelogEntry(
    version: '1.5.35',
    date: '15 Oktober 2026',
    changes: [
      'Upgrade AutoMix dengan beat-phase estimation offline, tempo matching per deck yang menjaga pitch, persiapan lagu berikutnya, dan bass hand-off saat crossfade.',
      'Transisi DJ-style tetap memakai crossfade biasa ketika analisis BPM atau fase ketukan kurang meyakinkan.',
    ],
  ),
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
