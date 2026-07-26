// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appName => 'Music Player';

  @override
  String get navHome => 'Beranda';

  @override
  String get navBrowse => 'Baru';

  @override
  String get navRadio => 'Radio';

  @override
  String get navLibrary => 'Perpustakaan';

  @override
  String get navSearch => 'Cari';

  @override
  String get cancel => 'Batal';

  @override
  String get save => 'Simpan';

  @override
  String get delete => 'Hapus';

  @override
  String get create => 'Buat';

  @override
  String get close => 'Tutup';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Coba Lagi';

  @override
  String get enabled => 'Aktif';

  @override
  String get disabled => 'Nonaktif';

  @override
  String get off => 'Nonaktif';

  @override
  String get done => 'Selesai';

  @override
  String get edit => 'Edit';

  @override
  String get rename => 'Ganti Nama';

  @override
  String get activate => 'Aktifkan';

  @override
  String get view => 'Lihat';

  @override
  String get testNow => 'Uji Sekarang';

  @override
  String get settings => 'Pengaturan';

  @override
  String get sectionAppearance => 'TAMPILAN';

  @override
  String get themeTitle => 'Tema';

  @override
  String get themeLight => 'Terang';

  @override
  String get themeAutomatic => 'Otomatis';

  @override
  String get themeDark => 'Gelap';

  @override
  String get showUpNext => 'Tampilkan Up Next';

  @override
  String get showUpNextSubtitle => 'Kartu lagu berikutnya di player';

  @override
  String get liquidGlass => 'Liquid Glass';

  @override
  String get liquidGlassSubtitle => 'Efek blur transparan pada seluruh UI';

  @override
  String get sectionLanguage => 'BAHASA';

  @override
  String get languageTitle => 'Bahasa';

  @override
  String get languageSystem => 'Sistem Default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get sectionAudio => 'AUDIO';

  @override
  String get audioNormalize => 'Audio Normalize';

  @override
  String get modeLabel => 'Mode';

  @override
  String get crossfeedTitle => 'Crossfeed';

  @override
  String get crossfeedActiveSubtitle =>
      'Simulasikan pencampuran kanal seperti speaker di headphone';

  @override
  String get crossfeedInactiveSubtitle =>
      'Aktifkan untuk headphone terasa lebih natural';

  @override
  String get crossfeedStrength => 'Kekuatan';

  @override
  String get crossfadeTitle => 'Crossfade';

  @override
  String crossfadeSeconds(String secs) {
    return '$secs detik';
  }

  @override
  String get stereoWidening => 'Stereo Widening';

  @override
  String get loudnessNormalization => 'Loudness Normalization';

  @override
  String get loudnessNormActiveSubtitle =>
      'Menyamakan kenyaringan secara real-time (EBU R128)';

  @override
  String get loudnessNormInactiveSubtitle =>
      'Normalisasi kenyaringan saat diputar';

  @override
  String loudnessTarget(String value) {
    return 'Target: $value LUFS';
  }

  @override
  String get loudnessHint => 'Streaming −14, Podcast −16, Broadcast −23';

  @override
  String get preamp => 'Preamp';

  @override
  String get clippingProtection => 'Clipping Protection';

  @override
  String get clippingProtectionSubtitle =>
      'Cegah distorsi saat gain melebihi 0 dBFS';

  @override
  String get replayGainTitle => 'Audio Normalize';

  @override
  String get replayGainModeLabel => 'Mode';

  @override
  String get replayGainPreampLabel => 'Preamp';

  @override
  String get replayGainOff => 'Off';

  @override
  String get replayGainAuto => 'Auto';

  @override
  String get replayGainTrack => 'Track Gain';

  @override
  String get replayGainAlbum => 'Album Gain';

  @override
  String get replayGainOffDesc => 'Tidak ada normalisasi volume';

  @override
  String get replayGainAutoDesc =>
      'Gunakan sumber loudness terbaik yang tersedia';

  @override
  String get replayGainTrackDesc => 'Normalisasi setiap lagu secara independen';

  @override
  String get replayGainAlbumDesc =>
      'Pertahankan hubungan volume antar lagu dalam album';

  @override
  String get scanLibrary => 'Scan Library';

  @override
  String get scanLibrarySubtitle =>
      'Hitung ReplayGain untuk lagu yang belum punya data';

  @override
  String get scanPreparing => 'Mempersiapkan...';

  @override
  String get noSongsInLibrary => 'Tidak ada lagu ditemukan di library.';

  @override
  String scanLibraryLoadFailed(String error) {
    return 'Gagal memuat library: $error';
  }

  @override
  String scanCancelled(int count) {
    return 'Dibatalkan · $count lagu berhasil';
  }

  @override
  String scanSuccess(int count) {
    return '$count lagu berhasil dipindai';
  }

  @override
  String scanPartial(int succeeded, int failed) {
    return '$succeeded berhasil, $failed gagal';
  }

  @override
  String get scanFailed => 'Gagal memindai lagu';

  @override
  String get sectionEqualizer => 'EQUALIZER';

  @override
  String get equalizerTitle => 'Equalizer';

  @override
  String get equalizerCustom => 'Custom';

  @override
  String get equalizerBitPerfect => 'Bit-Perfect';

  @override
  String get playbackSpeed => 'Kecepatan Putar';

  @override
  String get pitchShift => 'Pitch Shift';

  @override
  String get bassBoost => 'Bass Boost';

  @override
  String get compressor => 'Compressor';

  @override
  String get limiter => 'Limiter';

  @override
  String get softClipper => 'Soft Clipper';

  @override
  String get sectionBitPerfect => 'BIT-PERFECT';

  @override
  String get bitPerfectMode => 'Mode Bit-Perfect';

  @override
  String get bitPerfectActiveSubtitle =>
      'Aktif — semua pemrosesan audio dinonaktifkan';

  @override
  String get bitPerfectInactiveSubtitle =>
      'Nonaktifkan semua efek & pemrosesan audio';

  @override
  String get bitPerfectDescription =>
      'Semua efek dan pemrosesan audio di seluruh aplikasi akan dinonaktifkan paksa. Pengaturan yang sedang aktif akan disimpan dan dikembalikan otomatis saat mode ini dimatikan lagi.';

  @override
  String get bitPerfectConfirmTitle => 'Aktifkan Mode Bit-Perfect?';

  @override
  String get bitPerfectConfirmBody =>
      'Semua efek dan pemrosesan audio di seluruh aplikasi akan dinonaktifkan paksa. Pengaturan yang sedang aktif akan disimpan dan dikembalikan otomatis saat mode ini dimatikan lagi.';

  @override
  String get sectionSystem => 'SISTEM';

  @override
  String get activityLog => 'Log Aktivitas';

  @override
  String logEntryCount(int count) {
    return '$count entri';
  }

  @override
  String get sectionAbout => 'TENTANG';

  @override
  String get reportBug => 'Laporkan Bug';

  @override
  String get support => 'Dukungan';

  @override
  String get aboutApp => 'Tentang App';

  @override
  String get changelogTitle => 'Changelog';

  @override
  String get noChangelog => 'Belum ada perubahan tercatat';

  @override
  String get debugSection => 'MODE AKTIF';

  @override
  String get sessionStats => 'Statistik Sesi';

  @override
  String get exitDebugMode => 'Keluar Mode Debug';

  @override
  String get checkAAudio => 'Cek AAudio Exclusive/MMAP';

  @override
  String get aaudioNotTested =>
      'Belum diuji — buka stream nyata untuk melihat mode yang benar-benar diberikan OS';

  @override
  String get aaudioNotAvailablePlatform => 'Tidak tersedia di platform ini';

  @override
  String get aaudioNotAvailableAndroid =>
      'AAudio tidak tersedia (Android < 8.1)';

  @override
  String get aaudioTestFailed => 'Gagal menguji AAudio';

  @override
  String get debugModeEnabled => 'Mode Debug aktif';

  @override
  String get cantOpenLink => 'Tidak bisa membuka link';

  @override
  String get sleepTimerTitle => 'Sleep Timer';

  @override
  String get cancelTimer => 'Batalkan';

  @override
  String get sleepTimerActive => 'Sleep Timer Aktif';

  @override
  String get sleepAfterSong => 'Berhenti setelah lagu ini selesai';

  @override
  String get sleepFadeOut => 'Musik akan fade out perlahan saat timer habis';

  @override
  String get timerAfterSong => 'Timer: berhenti setelah lagu ini';

  @override
  String timerDuration(String label) {
    return 'Timer: $label';
  }

  @override
  String get upNextLabel => 'UP NEXT';

  @override
  String get shuffleOn => 'Shuffle On';

  @override
  String get shuffleOff => 'Shuffle Off';

  @override
  String get loopOff => 'Loop Off';

  @override
  String get loopAll => 'Loop All';

  @override
  String get loopOne => 'Loop One';

  @override
  String get songInfoLabel => 'Song Info';

  @override
  String get queueEmpty => 'Antrian kosong';

  @override
  String get continuePlaying => 'Lanjutkan Memutar';

  @override
  String get autoplayDescription => 'Memutar otomatis musik serupa';

  @override
  String get lyricsAppearance => 'Tampilan Lirik';

  @override
  String get textSizeLabel => 'Ukuran Teks';

  @override
  String get textAlignLabel => 'Rata Teks';

  @override
  String get activeColorLabel => 'Warna Aktif';

  @override
  String get karaokeHighlight => 'Highlight Karaoke';

  @override
  String get karaokeHighlightSubtitle => 'Animasi karakter per karakter';

  @override
  String get showLyricsSource => 'Tampilkan Sumber Lirik';

  @override
  String get playNow => 'Putar Sekarang';

  @override
  String get playNext => 'Putar Selanjutnya';

  @override
  String get addToQueue => 'Tambah ke Antrian';

  @override
  String get removeFromFavorites => 'Hapus dari Favorit';

  @override
  String get addToFavorites => 'Tambah ke Favorit';

  @override
  String get addToPlaylistMenu => 'Tambah ke Daftar Putar';

  @override
  String get openAlbum => 'Buka Album';

  @override
  String get openArtist => 'Buka Artis';

  @override
  String get songInformation => 'Informasi Lagu';

  @override
  String get deleteFromDevice => 'Hapus dari Perangkat';

  @override
  String get songDeletedMsg => 'Lagu berhasil dihapus';

  @override
  String get songDeleteFailedMsg => 'Gagal menghapus lagu';

  @override
  String get fieldTitle => 'Judul';

  @override
  String get fieldArtist => 'Artis';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldDuration => 'Durasi';

  @override
  String get addToPlaylistTitle => 'Tambah ke Daftar Putar';

  @override
  String get createNewPlaylist => 'Buat Daftar Putar Baru';

  @override
  String get noPlaylistsYet => 'Belum ada daftar putar';

  @override
  String addedToPlaylist(String name) {
    return 'Ditambahkan ke $name';
  }

  @override
  String get newPlaylistDialogTitle => 'Daftar Putar Baru';

  @override
  String get playlistNameHint => 'Nama Daftar Putar';

  @override
  String songCount(int count) {
    return '$count lagu';
  }

  @override
  String get renamePlaylist => 'Ganti Nama';

  @override
  String get deletePlaylistConfirm => 'Hapus Playlist?';

  @override
  String get deletePlaylist => 'Hapus Playlist';

  @override
  String get radioTitle => 'Radio';

  @override
  String get recentlyPlayed => 'Baru Dimainkan';

  @override
  String get noSongsYet => 'Belum ada lagu';

  @override
  String get myPlaylists => 'Playlist Saya';

  @override
  String get noPlaylistsCreated => 'Belum ada playlist';

  @override
  String get newPlaylist => 'Playlist Baru';

  @override
  String get favoritesLabel => 'Favorit';

  @override
  String get lastPlayedLabel => 'Diputar Terakhir';

  @override
  String get mostPlayedLabel => 'Paling Sering';

  @override
  String get libraryTitle => 'Perpustakaan';

  @override
  String get playlists => 'Daftar Putar';

  @override
  String get artists => 'Artis';

  @override
  String get albums => 'Album';

  @override
  String get songs => 'Lagu';

  @override
  String get searchInPlaylists => 'Cari di Daftar Putar';

  @override
  String get searchArtists => 'Cari Artis';

  @override
  String get searchAlbums => 'Cari Album';

  @override
  String get searchSongs => 'Cari Lagu';

  @override
  String get noLocalSongs => 'Tidak ada lagu lokal ditemukan';

  @override
  String get noSongsInList => 'Belum ada lagu';

  @override
  String get searchTitle => 'Cari';

  @override
  String get searchHint => 'Artis, Lagu, Album, dan lainnya';

  @override
  String noResults(String query) {
    return 'Tidak ada hasil untuk \"$query\"';
  }

  @override
  String get browseTitle => 'Baru';

  @override
  String get homeTitle => 'Beranda';

  @override
  String get noRecentSongs => 'Belum ada lagu yang diputar';

  @override
  String get noArtistsFound => 'Tidak ada artis ditemukan';

  @override
  String get favoriteArtists => 'Artis Favorit';

  @override
  String get topSongs => 'Top Songs';

  @override
  String get play => 'Putar';

  @override
  String get shuffle => 'Acak';

  @override
  String get playAll => 'Putar Semua';

  @override
  String get aboutTitle => 'Tentang App';

  @override
  String get musicPlayerName => 'Music Player';

  @override
  String appVersion(String version) {
    return 'Versi $version';
  }

  @override
  String get debugModeActiveLabel => 'Mode Debug Aktif';

  @override
  String get madeBy => 'Dibuat dengan dedikasi oleh';

  @override
  String get appDescription =>
      'Pemutar musik offline berbasis Flutter dengan sistem Audio Native Media3 Dual Exoplayer + Single Exoplayer.';

  @override
  String get releaseNotes => 'Catatan Pembaruan';

  @override
  String get bugReportTitle => 'Laporkan Bug';

  @override
  String get thankYouSupport => 'Terima kasih atas dukunganmu.';

  @override
  String get sendReportGmail => 'Kirim laporan kamu ke Gmail';

  @override
  String get orSocialMedia => 'atau ke akun sosial media di halaman Tentang.';

  @override
  String get playbackStatsTitle => 'Statistik Sesi Pemutaran';

  @override
  String get playbackStatsEngine => 'Engine: Native Media3';

  @override
  String get playTimeLabel => 'Waktu Putar';

  @override
  String get bufferingTimeLabel => 'Waktu Buffering';

  @override
  String get rebufferLabel => 'Rebuffer';

  @override
  String get errorLabel => 'Error';

  @override
  String get statsNotAvailable =>
      'Data tidak tersedia — mulai pemutaran terlebih dahulu.';

  @override
  String get timesUnit => 'kali';

  @override
  String get secondsZero => '0 dtk';

  @override
  String get goToSettings => 'Pengaturan';
}
