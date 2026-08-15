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
  String get audioNormalize => 'Normalisasi Audio';

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
  String get crossfadeTitle => 'Pudar Silang';

  @override
  String crossfadeSeconds(String secs) {
    return '$secs detik';
  }

  @override
  String get stereoWidening => 'Pelebaran Stereo';

  @override
  String get loudnessNormalization => 'Normalisasi Kenyaringan';

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
  String get clippingProtection => 'Pelindung Kliping';

  @override
  String get clippingProtectionSubtitle =>
      'Cegah distorsi saat gain melebihi 0 dBFS';

  @override
  String get replayGainTitle => 'Normalisasi Audio';

  @override
  String get replayGainModeLabel => 'Mode';

  @override
  String get replayGainPreampLabel => 'Preamp';

  @override
  String get replayGainOff => 'Off';

  @override
  String get replayGainAuto => 'Otomatis';

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
  String get statusNormalize => 'Normalisasi';

  @override
  String get statusBassBoost => 'Bass Boost';

  @override
  String get statusEqualizer => 'Equalizer';

  @override
  String get statusSpeed => 'Kecepatan';

  @override
  String get yes => 'Ya';

  @override
  String get logSearchHint => 'Cari pesan atau kategori…';

  @override
  String get logTitle => 'Log';

  @override
  String get liveLabel => 'LIVE';

  @override
  String get loudnessReplayGainTrack => 'ReplayGain (Track)';

  @override
  String get loudnessReplayGainAlbum => 'ReplayGain (Album)';

  @override
  String get loudnessR128Track => 'R128 (Track)';

  @override
  String get loudnessR128Album => 'R128 (Album)';

  @override
  String get loudnessITunNorm => 'iTunNORM';

  @override
  String get loudnessEmbedded => 'Tersemat';

  @override
  String get loudnessNone => 'Tidak ada';

  @override
  String get lyricsSourceEmbedded => 'Dari tag file';

  @override
  String get lyricsSourceLocalFile => 'Dari file .lrc';

  @override
  String get lyricsSourceInternet => 'Dari internet';

  @override
  String get lyricsTypeSynced => 'LRC (tersinkronisasi)';

  @override
  String get lyricsTypePlain => 'Teks biasa';

  @override
  String get lyricsQualityWordTimed => 'LRC dengan waktu per kata';

  @override
  String get lyricsQualityCharTimed => 'LRC dengan waktu per karakter';

  @override
  String get lyricsQualityLineTimed => 'LRC tersinkronisasi';

  @override
  String get lyricsQualityPlain => 'LRC biasa';

  @override
  String get lyricsQualityUnsynced => 'Tidak tersinkronisasi';

  @override
  String get lyricsQualityNone => 'Tidak ada';

  @override
  String get lyricsColorWhite => 'Putih';

  @override
  String get lyricsColorRed => 'Merah';

  @override
  String get lyricsColorYellow => 'Kuning';

  @override
  String sleepPresetMinutes(int minutes) {
    return '$minutes menit';
  }

  @override
  String sleepPresetHour(String hours) {
    return '$hours jam';
  }

  @override
  String get sleepPresetEndOfSong => 'Akhir lagu';

  @override
  String get sleepPresetSection => 'PILIH DURASI';

  @override
  String get scanLibrary => 'Pindai Perpustakaan';

  @override
  String get scanLibrarySubtitle =>
      'Hitung dan Tanamkan ReplayGain untuk lagu yang belum punya data';

  @override
  String get scanLibraryConfirmTitle => 'Pindai Perpustakaan?';

  @override
  String get scanLibraryConfirmBody =>
      'Perpustakan akan dipindai dan ditanamkan ReplayGain pada lagu yang belum memilikinya. Lanjutkan?';

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
  String get rgRemoveTagsAction => 'Hapus Tag ReplayGain';

  @override
  String get rgRemoveConfirmTitle => 'Hapus Tag ReplayGain?';

  @override
  String get rgRemoveConfirmBody =>
      'Tag ReplayGain/R128 akan dihapus dari semua lagu di library. Metadata lain tetap utuh.';

  @override
  String get rgRemoveRunning => 'Menghapus tag ReplayGain...';

  @override
  String rgRemoveLibrarySuccess(int count) {
    return '$count lagu dibersihkan';
  }

  @override
  String rgRemoveLibraryPartial(int removed, int failed) {
    return '$removed dibersihkan, $failed gagal';
  }

  @override
  String get rgRemoveFailed => 'Gagal menghapus tag ReplayGain';

  @override
  String get sectionEqualizer => 'EQUALIZER';

  @override
  String get equalizerTitle => 'Equalizer';

  @override
  String get equalizerCustom => 'Custom';

  @override
  String get equalizerBitPerfect => 'Audio Bersih';

  @override
  String get playbackSpeed => 'Kecepatan Putar';

  @override
  String get pitchShift => 'Pergeseran Nada';

  @override
  String get bassBoost => 'Bass Boost';

  @override
  String get compressor => 'Kompresor';

  @override
  String get limiter => 'Pembatas';

  @override
  String get softClipper => 'Kliping Halus';

  @override
  String get sectionBitPerfect => 'PEMUTAR';

  @override
  String get bitPerfectMode => 'Mode Pemutar Bersih';

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
  String get bitPerfectConfirmTitle => 'Aktifkan Mode Audio Bersih?';

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
  String get debugLabel => 'DEBUG';

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
  String get qrisSaveTitle => 'Simpan QR Code';

  @override
  String get qrisSavePrompt => 'Simpan gambar QRIS ke galeri?';

  @override
  String get qrisGalleryDenied =>
      'Izin galeri ditolak — aktifkan di Pengaturan › Izin Aplikasi';

  @override
  String get qrisSavedToGallery => 'Gambar berhasil disimpan ke galeri';

  @override
  String get qrisAccessDenied => 'Akses galeri ditolak';

  @override
  String get qrisNotEnoughSpace => 'Ruang penyimpanan penuh';

  @override
  String get qrisFormatUnsupported => 'Format tidak didukung';

  @override
  String get qrisUnexpectedError => 'Error tidak terduga dari galeri';

  @override
  String qrisSaveFailed(String reason) {
    return 'Gagal menyimpan: $reason';
  }

  @override
  String get sleepTimerTitle => 'Sleep Timer';

  @override
  String get cancelTimer => 'Batalkan';

  @override
  String get sleepTimerActive => 'Sleep Timer Aktif';

  @override
  String get sleepAfterSong => 'Berhenti setelah lagu ini selesai';

  @override
  String get sleepFadeOut => 'Musik akan memudar perlahan saat timer habis';

  @override
  String get sleepFadingOut => 'Memudar…';

  @override
  String get timerAfterSong => 'Timer: berhenti setelah lagu ini';

  @override
  String timerDuration(String label) {
    return 'Timer: $label';
  }

  @override
  String get upNextLabel => 'BERIKUTNYA';

  @override
  String get shuffleOn => 'Shuffle On';

  @override
  String get shuffleOff => 'Shuffle Off';

  @override
  String get loopOff => 'Loop Mati';

  @override
  String get loopAll => 'Loop Semua';

  @override
  String get loopOne => 'Loop Satu';

  @override
  String get songInfoLabel => 'Info Lagu';

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
  String get deletePlaylistConfirm => 'Hapus Daftar Lagu?';

  @override
  String get deletePlaylist => 'Hapus Playlist';

  @override
  String get radioTitle => 'Radio';

  @override
  String get recentlyPlayed => 'Baru Dimainkan';

  @override
  String get noSongsYet => 'Belum ada lagu';

  @override
  String get myPlaylists => 'Daftar Lagu Saya';

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
  String get noRecentlyPlayed => 'Belum ada lagu yang baru diputar';

  @override
  String searchNoResults(String query) {
    return 'Tidak ada hasil untuk \"$query\"';
  }

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
  String get sendReportGmail => 'Kirim laporan kamu ke';

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

  @override
  String deletePlaylistBody(String name) {
    return 'Playlist \"$name\" akan dihapus permanen.';
  }

  @override
  String get timerEndOfSong => 'Akhir lagu';

  @override
  String get sectionDetails => 'DETAIL';

  @override
  String get sectionAudioQuality => 'KUALITAS AUDIO';

  @override
  String get sectionLoudness => 'KENYARINGAN';

  @override
  String get sectionEmbedded => 'KONTEN TERSEMAT';

  @override
  String get sectionStatistics => 'STATISTIK';

  @override
  String get sectionFile => 'FILE';

  @override
  String get sectionAdditionalInfo => 'INFO TAMBAHAN';

  @override
  String get fieldAlbumArtist => 'Artis Album';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get fieldYear => 'Tahun';

  @override
  String get fieldTrack => 'Track';

  @override
  String trackDiscValue(String track, String disc) {
    return '$track (Disc $disc)';
  }

  @override
  String get fieldFormat => 'Format';

  @override
  String get fieldBitDepth => 'Kedalaman Bit';

  @override
  String get fieldSampleRate => 'Laju Sampel';

  @override
  String get fieldChannels => 'Saluran';

  @override
  String get fieldBitrate => 'Laju Bit';

  @override
  String get fieldEncoder => 'Encoder';

  @override
  String get fieldFileSize => 'Ukuran File';

  @override
  String get fieldAppliedGain => 'Gain Diterapkan';

  @override
  String get fieldLoudnessSource => 'Sumber';

  @override
  String get fieldLyrics => 'Lirik';

  @override
  String get fieldPlayCount => 'Jumlah Putar';

  @override
  String get fieldFileName => 'Nama File';

  @override
  String get fieldFilePath => 'Lokasi File';

  @override
  String get fieldFolder => 'Folder';

  @override
  String get fieldDateAdded => 'Tanggal Ditambahkan';

  @override
  String get fieldModified => 'Dimodifikasi';

  @override
  String get fieldComposer => 'Komposer';

  @override
  String get fieldPublisher => 'Penerbit';

  @override
  String get fieldCopyright => 'Hak Cipta';

  @override
  String get fieldIsrc => 'ISRC';

  @override
  String get fieldComment => 'Komentar';

  @override
  String get fieldRgTrackGain => 'RG Track Gain';

  @override
  String get fieldRgTrackPeak => 'RG Track Peak';

  @override
  String get fieldRgAlbumGain => 'RG Album Gain';

  @override
  String get fieldRgAlbumPeak => 'RG Album Peak';

  @override
  String get fieldR128TrackGain => 'R128 Track Gain';

  @override
  String get fieldR128AlbumGain => 'R128 Album Gain';

  @override
  String get channelMono => 'Mono';

  @override
  String get channelStereo => 'Stereo';

  @override
  String get channelQuad => 'Quad';

  @override
  String get channel51Surround => '5.1 Surround';

  @override
  String get channel71Surround => '7.1 Surround';

  @override
  String get bitrateUnknownLossless => 'Lossless';

  @override
  String get glassToggleNavBar => 'NavBar';

  @override
  String get glassToggleAppBar => 'AppBar';

  @override
  String get glassToggleMiniPlayer => 'Mini Player';

  @override
  String get glassToggleAlbumCard => 'Album Card';

  @override
  String get logLevelTitle => 'Level Log';

  @override
  String get logLevelOff => 'Nonaktif';

  @override
  String get logLevelOffDesc => 'Logging dimatikan';

  @override
  String get logLevelErrorsOnly => 'Error & Peringatan Saja';

  @override
  String get logLevelErrorsOnlyDesc => 'Sembunyikan log info & verbose';

  @override
  String get logLevelNormal => 'Normal';

  @override
  String get logLevelNormalDesc => 'Log info, error & peringatan';

  @override
  String get logLevelVerbose => 'Log Verbose';

  @override
  String get logLevelVerboseDesc => 'Tampilkan log detail';

  @override
  String get clearLogsConfirm => 'Hapus semua log?';

  @override
  String get logScrollTop => 'Atas';

  @override
  String get logScrollBottom => 'Bawah';

  @override
  String get logCopyAll => 'Salin semua';

  @override
  String get logNoResults => 'tidak ada hasil';

  @override
  String get logEmpty => 'belum ada log';

  @override
  String logCopiedEntries(int count) {
    return '$count entri disalin';
  }

  @override
  String get logCopiedEntry => 'Entri disalin';

  @override
  String songsFoundMsg(int count) {
    return 'Ditemukan $count lagu';
  }

  @override
  String get rescanSongs => 'Scan Ulang Lagu';

  @override
  String get cantOpenEmail => 'Tidak bisa membuka aplikasi email';

  @override
  String get audioEngineInfo => 'Info Audio Engine';

  @override
  String get activeEffectsStatus => 'Status Efek Aktif';

  @override
  String get weRecommend => 'Kami Rekomendasikan';

  @override
  String get newMusicSection => 'Musik Baru';

  @override
  String get dailyTop100 => 'Top Harian';

  @override
  String get tvAndFilm => 'TV & Film';

  @override
  String get reset => 'Reset';

  @override
  String get normal => 'Normal';

  @override
  String get notSupportedDevice => 'Tidak didukung perangkat ini';

  @override
  String get hardKnee => 'Hard knee';

  @override
  String get noPlaylists => 'Belum ada daftar putar';

  @override
  String get bugReportParagraph1 =>
      'Kalau kamu menemukan bug, error, crash, atau ada fitur yang tidak bekerja sebagaimana mestinya, mohon laporkan agar bisa segera diperbaiki.';

  @override
  String get bugReportParagraph2 =>
      'Kamu juga bisa mengirimkan saran, masukan, atau permintaan fitur baru. Setiap laporan sangat membantu dalam meningkatkan kualitas aplikasi.';

  @override
  String get speedDesc =>
      'Mengatur kecepatan pemutaran lagu. Nilai di bawah 1x memperlambat, di atas 1x mempercepat, tanpa mengubah pitch suara.';

  @override
  String get pitchDesc =>
      'Menaikkan atau menurunkan nada lagu dalam satuan semitone, tanpa mengubah kecepatan putar.';

  @override
  String get bassBoostDesc =>
      'Menguatkan frekuensi bass agar suara dentum/rendah terasa lebih tebal. Semakin besar persentase, semakin kuat efeknya.';

  @override
  String get preampDesc =>
      'Menyesuaikan volume dasar sebelum EQ dan efek lain diproses. Geser ke kanan untuk menaikkan, ke kiri untuk menurunkan.';

  @override
  String get compressorDesc =>
      'Menekan perbedaan volume antara suara pelan dan keras. Rasio lebih tinggi = kompresi lebih agresif. 1:1 berarti nonaktif.';

  @override
  String get compressorThresholdTitle => 'Compressor Threshold';

  @override
  String get compressorThresholdDesc =>
      'Ambang batas volume tempat compressor mulai bekerja. Semakin rendah nilainya, semakin banyak bagian suara yang dikompres.';

  @override
  String get compressorAttackTitle => 'Compressor Attack';

  @override
  String get compressorAttackDesc =>
      'Seberapa cepat compressor bereaksi saat suara melewati threshold. Lebih cepat = lebih responsif terhadap suara mendadak.';

  @override
  String get compressorReleaseTitle => 'Compressor Release';

  @override
  String get compressorReleaseDesc =>
      'Seberapa cepat volume kembali normal setelah kompresi. Terlalu cepat bisa terdengar \"berpompa\".';

  @override
  String get compressorKneeTitle => 'Compressor Knee';

  @override
  String get compressorKneeDesc =>
      'Melembutkan transisi masuk ke kompresi di sekitar threshold. 0 dB = transisi tegas (hard knee).';

  @override
  String get limiterDesc =>
      'Mencegah suara melewati batas volume tertentu agar tidak pecah/distorsi. Geser di bawah 0 dB untuk mengaktifkan.';

  @override
  String get limiterReleaseTitle => 'Limiter Release';

  @override
  String get limiterReleaseDesc =>
      'Seberapa cepat limiter melepas setelah menahan puncak suara. Terlalu cepat bisa terdengar tidak alami.';

  @override
  String get softClipperDesc =>
      'Melunakkan puncak suara yang terlalu keras secara halus, sebagai lapisan pengaman terakhir sebelum output, sehingga distorsi lebih tidak terasa dibanding limiter.';

  @override
  String get dspPipeline => 'DSP Pipeline';

  @override
  String get androidDsp => 'Android DSP';

  @override
  String get webFallback => 'Web / Fallback';

  @override
  String get supported => 'Didukung';

  @override
  String get unavailable => 'Tidak tersedia';

  @override
  String durationSeconds(int seconds) {
    return '$seconds dtk';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationHoursMinutesSeconds(int hours, int minutes, int seconds) {
    return '${hours}j ${minutes}m ${seconds}d';
  }

  @override
  String get lyricsNotFound => 'Lirik tidak ditemukan';

  @override
  String get lyricsFileHint =>
      'Tambahkan file .lrc di folder yang sama dengan lagu, atau konfigurasikan folder lirik di Pengaturan.';

  @override
  String get noSongSelected => 'Belum ada lagu yang dipilih';

  @override
  String get lockedInactive =>
      'Kontrol dikunci — Mode Bit-Perfect sedang aktif';

  @override
  String get bandEq => 'BAND EQ';

  @override
  String get preset => 'PRESET';

  @override
  String pitchSemitone(String value) {
    return '$value semitone';
  }

  @override
  String decibelValue(String value) {
    return '$value dB';
  }

  @override
  String millisecondsValue(String value) {
    return '$value ms';
  }

  @override
  String get crossfadeOptionOff => 'Mati';

  @override
  String crossfadeOptionSeconds(String seconds) {
    return '${seconds}d';
  }

  @override
  String get listenAgain => 'Dengarkan Lagi';

  @override
  String moreFromArtist(String artist) {
    return 'Lainnya dari $artist';
  }

  @override
  String get topPicks => 'Pilihan Teratas Untukmu';

  @override
  String songsByArtist(int songs, int albums) {
    return '$songs lagu • $albums album';
  }

  @override
  String get lossless => 'Lossless';

  @override
  String get contentUnavailable => 'Belum ada konten';

  @override
  String playedCount(int count) {
    return 'Diputar ${count}x';
  }

  @override
  String copyrightFooter(int year) {
    return '© $year Flutter Music App dengan Media3 ExoPlayer';
  }

  @override
  String get logFilterAll => 'SEMUA';

  @override
  String get logFilterError => 'ERR';

  @override
  String get logFilterWarning => 'WRN';

  @override
  String get logFilterInfo => 'INF';

  @override
  String get logFilterVerbose => 'VRB';

  @override
  String get logBadgeOff => 'NONAKTIF';

  @override
  String get logBadgeError => 'ERR';

  @override
  String get logBadgeVerbose => 'VRB';

  @override
  String get logBadgeNormal => 'LOG';

  @override
  String songsCount(int count) {
    return '$count lagu';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours jam $minutes menit';
  }

  @override
  String durationOnlyMinutes(int minutes) {
    return '$minutes menit';
  }

  @override
  String albumSongsAndDuration(int count, String duration) {
    return '$count lagu, $duration';
  }

  @override
  String get madeByShort => 'Dibuat Oleh';
}
