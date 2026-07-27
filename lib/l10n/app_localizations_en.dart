// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Music Player';

  @override
  String get navHome => 'Home';

  @override
  String get navBrowse => 'Browse';

  @override
  String get navRadio => 'Radio';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSearch => 'Search';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get create => 'Create';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Retry';

  @override
  String get enabled => 'Active';

  @override
  String get disabled => 'Inactive';

  @override
  String get off => 'Off';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get rename => 'Rename';

  @override
  String get activate => 'Activate';

  @override
  String get view => 'View';

  @override
  String get testNow => 'Test Now';

  @override
  String get settings => 'Settings';

  @override
  String get sectionAppearance => 'APPEARANCE';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeAutomatic => 'Automatic';

  @override
  String get themeDark => 'Dark';

  @override
  String get showUpNext => 'Show Up Next';

  @override
  String get showUpNextSubtitle => 'Next song card in player';

  @override
  String get liquidGlass => 'Liquid Glass';

  @override
  String get liquidGlassSubtitle => 'Transparent blur effect on the entire UI';

  @override
  String get sectionLanguage => 'LANGUAGE';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System Default';

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
      'Simulates speaker-like channel blending for headphones';

  @override
  String get crossfeedInactiveSubtitle =>
      'Enable for more natural headphone listening';

  @override
  String get crossfeedStrength => 'Strength';

  @override
  String get crossfadeTitle => 'Crossfade';

  @override
  String crossfadeSeconds(String secs) {
    return '$secs seconds';
  }

  @override
  String get stereoWidening => 'Stereo Widening';

  @override
  String get loudnessNormalization => 'Loudness Normalization';

  @override
  String get loudnessNormActiveSubtitle =>
      'Equalizes loudness in real-time (EBU R128)';

  @override
  String get loudnessNormInactiveSubtitle =>
      'Normalize loudness during playback';

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
      'Prevent distortion when gain exceeds 0 dBFS';

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
  String get replayGainOffDesc => 'No volume normalization';

  @override
  String get replayGainAutoDesc => 'Use the best available loudness source';

  @override
  String get replayGainTrackDesc => 'Normalize each song independently';

  @override
  String get replayGainAlbumDesc =>
      'Maintain volume relationship between songs in an album';

  @override
  String get statusNormalize => 'Normalize';

  @override
  String get statusBassBoost => 'Bass Boost';

  @override
  String get statusEqualizer => 'Equalizer';

  @override
  String get statusSpeed => 'Speed';

  @override
  String get yes => 'Yes';

  @override
  String get logSearchHint => 'Search messages or categories…';

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
  String get loudnessEmbedded => 'Embedded';

  @override
  String get loudnessNone => 'None';

  @override
  String get lyricsSourceEmbedded => 'From file tags';

  @override
  String get lyricsSourceLocalFile => 'From .lrc file';

  @override
  String get lyricsSourceInternet => 'From internet';

  @override
  String get lyricsTypeSynced => 'LRC (synced)';

  @override
  String get lyricsTypePlain => 'Plain text';

  @override
  String get lyricsQualityWordTimed => 'Word-timed LRC';

  @override
  String get lyricsQualityCharTimed => 'Char-timed LRC';

  @override
  String get lyricsQualityLineTimed => 'Synced LRC';

  @override
  String get lyricsQualityPlain => 'Plain LRC';

  @override
  String get lyricsQualityUnsynced => 'Unsynced';

  @override
  String get lyricsQualityNone => 'None';

  @override
  String get lyricsColorWhite => 'White';

  @override
  String get lyricsColorRed => 'Red';

  @override
  String get lyricsColorYellow => 'Yellow';

  @override
  String sleepPresetMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String sleepPresetHour(String hours) {
    return '$hours hour';
  }

  @override
  String get sleepPresetEndOfSong => 'End of song';

  @override
  String get sleepPresetSection => 'CHOOSE DURATION';

  @override
  String get scanLibrary => 'Scan Library';

  @override
  String get scanLibrarySubtitle =>
      'Calculate ReplayGain for songs without data';

  @override
  String get scanPreparing => 'Preparing...';

  @override
  String get noSongsInLibrary => 'No songs found in library.';

  @override
  String scanLibraryLoadFailed(String error) {
    return 'Failed to load library: $error';
  }

  @override
  String scanCancelled(int count) {
    return 'Cancelled · $count songs succeeded';
  }

  @override
  String scanSuccess(int count) {
    return '$count songs scanned successfully';
  }

  @override
  String scanPartial(int succeeded, int failed) {
    return '$succeeded succeeded, $failed failed';
  }

  @override
  String get scanFailed => 'Failed to scan songs';

  @override
  String get sectionEqualizer => 'EQUALIZER';

  @override
  String get equalizerTitle => 'Equalizer';

  @override
  String get equalizerCustom => 'Custom';

  @override
  String get equalizerBitPerfect => 'Bit-Perfect';

  @override
  String get playbackSpeed => 'Playback Speed';

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
  String get bitPerfectMode => 'Bit-Perfect Mode';

  @override
  String get bitPerfectActiveSubtitle =>
      'Active — all audio processing disabled';

  @override
  String get bitPerfectInactiveSubtitle =>
      'Disable all effects & audio processing';

  @override
  String get bitPerfectDescription =>
      'All effects and audio processing throughout the app will be forcibly disabled. Active settings will be saved and automatically restored when this mode is turned off.';

  @override
  String get bitPerfectConfirmTitle => 'Activate Bit-Perfect Mode?';

  @override
  String get bitPerfectConfirmBody =>
      'All effects and audio processing throughout the app will be forcibly disabled. Active settings will be saved and automatically restored when this mode is turned off.';

  @override
  String get sectionSystem => 'SYSTEM';

  @override
  String get activityLog => 'Activity Log';

  @override
  String logEntryCount(int count) {
    return '$count entries';
  }

  @override
  String get sectionAbout => 'ABOUT';

  @override
  String get reportBug => 'Report Bug';

  @override
  String get support => 'Support';

  @override
  String get aboutApp => 'About App';

  @override
  String get changelogTitle => 'Changelog';

  @override
  String get noChangelog => 'No changes recorded yet';

  @override
  String get debugSection => 'MODE ACTIVE';

  @override
  String get debugLabel => 'DEBUG';

  @override
  String get sessionStats => 'Session Statistics';

  @override
  String get exitDebugMode => 'Exit Debug Mode';

  @override
  String get checkAAudio => 'Check AAudio Exclusive/MMAP';

  @override
  String get aaudioNotTested =>
      'Not tested — open a real stream to see the mode actually granted by the OS';

  @override
  String get aaudioNotAvailablePlatform => 'Not available on this platform';

  @override
  String get aaudioNotAvailableAndroid =>
      'AAudio not available (Android < 8.1)';

  @override
  String get aaudioTestFailed => 'Failed to test AAudio';

  @override
  String get debugModeEnabled => 'Debug mode enabled';

  @override
  String get cantOpenLink => 'Cannot open link';

  @override
  String get sleepTimerTitle => 'Sleep Timer';

  @override
  String get cancelTimer => 'Cancel';

  @override
  String get sleepTimerActive => 'Sleep Timer Active';

  @override
  String get sleepAfterSong => 'Stop after this song ends';

  @override
  String get sleepFadeOut => 'Music will fade out slowly when the timer ends';

  @override
  String get timerAfterSong => 'Timer: stop after this song';

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
  String get queueEmpty => 'Queue is empty';

  @override
  String get continuePlaying => 'Continue Playing';

  @override
  String get autoplayDescription => 'Auto-playing similar music';

  @override
  String get lyricsAppearance => 'Lyrics Appearance';

  @override
  String get textSizeLabel => 'Text Size';

  @override
  String get textAlignLabel => 'Text Alignment';

  @override
  String get activeColorLabel => 'Active Color';

  @override
  String get karaokeHighlight => 'Karaoke Highlight';

  @override
  String get karaokeHighlightSubtitle => 'Character-by-character animation';

  @override
  String get showLyricsSource => 'Show Lyrics Source';

  @override
  String get playNow => 'Play Now';

  @override
  String get playNext => 'Play Next';

  @override
  String get addToQueue => 'Add to Queue';

  @override
  String get removeFromFavorites => 'Remove from Favorites';

  @override
  String get addToFavorites => 'Add to Favorites';

  @override
  String get addToPlaylistMenu => 'Add to Playlist';

  @override
  String get openAlbum => 'Open Album';

  @override
  String get openArtist => 'Open Artist';

  @override
  String get songInformation => 'Song Information';

  @override
  String get deleteFromDevice => 'Delete from Device';

  @override
  String get songDeletedMsg => 'Song deleted successfully';

  @override
  String get songDeleteFailedMsg => 'Failed to delete song';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldArtist => 'Artist';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldDuration => 'Duration';

  @override
  String get addToPlaylistTitle => 'Add to Playlist';

  @override
  String get createNewPlaylist => 'Create New Playlist';

  @override
  String get noPlaylistsYet => 'No playlists yet';

  @override
  String addedToPlaylist(String name) {
    return 'Added to $name';
  }

  @override
  String get newPlaylistDialogTitle => 'New Playlist';

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String songCount(int count) {
    return '$count songs';
  }

  @override
  String get renamePlaylist => 'Rename';

  @override
  String get deletePlaylistConfirm => 'Delete Playlist?';

  @override
  String get deletePlaylist => 'Delete Playlist';

  @override
  String get radioTitle => 'Radio';

  @override
  String get recentlyPlayed => 'Recently Played';

  @override
  String get noSongsYet => 'No songs yet';

  @override
  String get myPlaylists => 'My Playlists';

  @override
  String get noPlaylistsCreated => 'No playlists yet';

  @override
  String get newPlaylist => 'New Playlist';

  @override
  String get favoritesLabel => 'Favorites';

  @override
  String get lastPlayedLabel => 'Last Played';

  @override
  String get mostPlayedLabel => 'Most Played';

  @override
  String get libraryTitle => 'Library';

  @override
  String get playlists => 'Playlists';

  @override
  String get artists => 'Artists';

  @override
  String get albums => 'Albums';

  @override
  String get songs => 'Songs';

  @override
  String get searchInPlaylists => 'Search in Playlists';

  @override
  String get searchArtists => 'Search Artists';

  @override
  String get searchAlbums => 'Search Albums';

  @override
  String get searchSongs => 'Search Songs';

  @override
  String get noLocalSongs => 'No local songs found';

  @override
  String get noSongsInList => 'No songs yet';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Artists, Songs, Albums, and more';

  @override
  String noResults(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get browseTitle => 'Browse';

  @override
  String get homeTitle => 'Home';

  @override
  String get noRecentSongs => 'No songs played yet';

  @override
  String get noRecentlyPlayed => 'No recently played songs';

  @override
  String searchNoResults(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get noArtistsFound => 'No artists found';

  @override
  String get favoriteArtists => 'Favorite Artists';

  @override
  String get topSongs => 'Top Songs';

  @override
  String get play => 'Play';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get playAll => 'Play All';

  @override
  String get aboutTitle => 'About App';

  @override
  String get musicPlayerName => 'Music Player';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get debugModeActiveLabel => 'Debug Mode Active';

  @override
  String get madeBy => 'Made with dedication by';

  @override
  String get appDescription =>
      'Offline music player based on Flutter with Native Media3 Dual Exoplayer + Single Exoplayer Audio system.';

  @override
  String get releaseNotes => 'Release Notes';

  @override
  String get bugReportTitle => 'Report Bug';

  @override
  String get thankYouSupport => 'Thank you for your support.';

  @override
  String get sendReportGmail => 'Send your report to Gmail';

  @override
  String get orSocialMedia =>
      'or to the social media accounts on the About page.';

  @override
  String get playbackStatsTitle => 'Playback Session Statistics';

  @override
  String get playbackStatsEngine => 'Engine: Native Media3';

  @override
  String get playTimeLabel => 'Play Time';

  @override
  String get bufferingTimeLabel => 'Buffering Time';

  @override
  String get rebufferLabel => 'Rebuffer';

  @override
  String get errorLabel => 'Error';

  @override
  String get statsNotAvailable => 'Data not available — start playback first.';

  @override
  String get timesUnit => 'times';

  @override
  String get secondsZero => '0 sec';

  @override
  String get goToSettings => 'Settings';

  @override
  String deletePlaylistBody(String name) {
    return 'Playlist \"$name\" will be permanently deleted.';
  }

  @override
  String get timerEndOfSong => 'End of song';

  @override
  String get sectionDetails => 'DETAILS';

  @override
  String get sectionAudioQuality => 'AUDIO QUALITY';

  @override
  String get sectionLoudness => 'LOUDNESS';

  @override
  String get sectionEmbedded => 'EMBEDDED CONTENT';

  @override
  String get sectionStatistics => 'STATISTICS';

  @override
  String get sectionFile => 'FILE';

  @override
  String get sectionAdditionalInfo => 'ADDITIONAL INFO';

  @override
  String get fieldAlbumArtist => 'Album Artist';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get fieldYear => 'Year';

  @override
  String get fieldTrack => 'Track';

  @override
  String trackDiscValue(String track, String disc) {
    return '$track (Disc $disc)';
  }

  @override
  String get fieldFormat => 'Format';

  @override
  String get fieldBitDepth => 'Bit Depth';

  @override
  String get fieldSampleRate => 'Sample Rate';

  @override
  String get fieldChannels => 'Channels';

  @override
  String get fieldBitrate => 'Bitrate';

  @override
  String get fieldEncoder => 'Encoder';

  @override
  String get fieldFileSize => 'File Size';

  @override
  String get fieldAppliedGain => 'Applied Gain';

  @override
  String get fieldLoudnessSource => 'Source';

  @override
  String get fieldLyrics => 'Lyrics';

  @override
  String get fieldPlayCount => 'Play Count';

  @override
  String get fieldFileName => 'File Name';

  @override
  String get fieldFilePath => 'File Path';

  @override
  String get fieldFolder => 'Folder';

  @override
  String get fieldDateAdded => 'Date Added';

  @override
  String get fieldModified => 'Modified';

  @override
  String get fieldComposer => 'Composer';

  @override
  String get fieldPublisher => 'Publisher';

  @override
  String get fieldCopyright => 'Copyright';

  @override
  String get fieldIsrc => 'ISRC';

  @override
  String get fieldComment => 'Comment';

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
  String get glassTogglePlayerSheet => 'Player Sheet';

  @override
  String get glassToggleAlbumCard => 'Album Card';

  @override
  String get logLevelTitle => 'Log Level';

  @override
  String get logLevelOff => 'Off';

  @override
  String get logLevelOffDesc => 'Logging disabled';

  @override
  String get logLevelErrorsOnly => 'Errors & Warnings Only';

  @override
  String get logLevelErrorsOnlyDesc => 'Hide info & verbose logs';

  @override
  String get logLevelNormal => 'Normal';

  @override
  String get logLevelNormalDesc => 'Log info, errors & warnings';

  @override
  String get logLevelVerbose => 'Verbose Log';

  @override
  String get logLevelVerboseDesc => 'Show detailed logs';

  @override
  String get clearLogsConfirm => 'Clear all logs?';

  @override
  String get logScrollTop => 'Top';

  @override
  String get logScrollBottom => 'Bottom';

  @override
  String get logCopyAll => 'Copy all';

  @override
  String get logNoResults => 'no results';

  @override
  String get logEmpty => 'no logs yet';

  @override
  String logCopiedEntries(int count) {
    return '$count entries copied';
  }

  @override
  String get logCopiedEntry => 'Entry copied';

  @override
  String songsFoundMsg(int count) {
    return 'Found $count songs';
  }

  @override
  String get rescanSongs => 'Rescan Songs';

  @override
  String get cantOpenEmail => 'Cannot open email app';

  @override
  String get audioEngineInfo => 'Audio Engine Info';

  @override
  String get activeEffectsStatus => 'Active Effects Status';

  @override
  String get weRecommend => 'We Recommend';

  @override
  String get newMusicSection => 'New Music';

  @override
  String get dailyTop100 => 'Daily Top 100';

  @override
  String get tvAndFilm => 'TV & Film';

  @override
  String get reset => 'Reset';

  @override
  String get normal => 'Normal';

  @override
  String get notSupportedDevice => 'Not supported on this device';

  @override
  String get hardKnee => 'Hard knee';

  @override
  String get noPlaylists => 'No playlists yet';

  @override
  String get bugReportParagraph1 =>
      'If you find a bug, error, crash, or something not working as expected, please report it so it can be fixed quickly.';

  @override
  String get bugReportParagraph2 =>
      'You can also send suggestions, feedback, or new feature requests. Every report helps improve the app quality.';

  @override
  String get speedDesc =>
      'Adjusts song playback speed. Below 1x slows down, above 1x speeds up, without changing pitch.';

  @override
  String get pitchDesc =>
      'Raises or lowers the song pitch in semitones, without changing playback speed.';

  @override
  String get bassBoostDesc =>
      'Boosts bass frequencies for a deeper, thicker low-end sound. Higher percentage = stronger effect.';

  @override
  String get preampDesc =>
      'Adjusts the base volume before EQ and other effects are processed. Slide right to raise, left to lower.';

  @override
  String get compressorDesc =>
      'Reduces the volume difference between quiet and loud sounds. Higher ratio = more aggressive compression. 1:1 means off.';

  @override
  String get compressorThresholdTitle => 'Compressor Threshold';

  @override
  String get compressorThresholdDesc =>
      'The volume level where compression kicks in. Lower value = more audio compressed.';

  @override
  String get compressorAttackTitle => 'Compressor Attack';

  @override
  String get compressorAttackDesc =>
      'How quickly the compressor reacts when audio exceeds the threshold. Faster = more responsive to sudden sounds.';

  @override
  String get compressorReleaseTitle => 'Compressor Release';

  @override
  String get compressorReleaseDesc =>
      'How quickly volume returns to normal after compression. Too fast can sound \'pumpy\'.';

  @override
  String get compressorKneeTitle => 'Compressor Knee';

  @override
  String get compressorKneeDesc =>
      'Softens the transition into compression around the threshold. 0 dB = hard knee.';

  @override
  String get limiterDesc =>
      'Prevents audio from exceeding a set volume level to avoid clipping/distortion. Slide below 0 dB to activate.';

  @override
  String get limiterReleaseTitle => 'Limiter Release';

  @override
  String get limiterReleaseDesc =>
      'How quickly the limiter releases after capping a peak. Too fast can sound unnatural.';

  @override
  String get softClipperDesc =>
      'Gently rounds off excessively loud peaks as a final safety layer before output, making distortion less noticeable than a limiter.';

  @override
  String get dspPipeline => 'DSP Pipeline';

  @override
  String get androidDsp => 'Android DSP';

  @override
  String get webFallback => 'Web / Fallback';

  @override
  String get supported => 'Supported ✓';

  @override
  String get unavailable => 'Unavailable ✗';

  @override
  String durationSeconds(int seconds) {
    return '$seconds sec';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationHoursMinutesSeconds(int hours, int minutes, int seconds) {
    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  String get lyricsNotFound => 'Lyrics not found';

  @override
  String get lyricsFileHint =>
      'Add an .lrc file in the same folder as the song, or configure the lyrics folder in Settings.';

  @override
  String get noSongSelected => 'No song selected';

  @override
  String get lockedInactive => 'Controls locked — Bit-Perfect Mode is active';

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
  String get crossfadeOptionOff => 'Off';

  @override
  String crossfadeOptionSeconds(String seconds) {
    return '${seconds}s';
  }

  @override
  String get listenAgain => 'Listen Again';

  @override
  String moreFromArtist(String artist) {
    return 'More from $artist';
  }

  @override
  String get topPicks => 'Top Picks For You';

  @override
  String songsByArtist(int songs, int albums) {
    return '$songs songs • $albums albums';
  }

  @override
  String get lossless => 'Lossless';

  @override
  String get contentUnavailable => 'No content yet';

  @override
  String playedCount(int count) {
    return 'Played ${count}x';
  }

  @override
  String copyrightFooter(int year) {
    return '© $year Flutter Music App with Media3 ExoPlayer';
  }

  @override
  String get logFilterAll => 'ALL';

  @override
  String get logFilterError => 'ERR';

  @override
  String get logFilterWarning => 'WRN';

  @override
  String get logFilterInfo => 'INF';

  @override
  String get logFilterVerbose => 'VRB';

  @override
  String get logBadgeOff => 'OFF';

  @override
  String get logBadgeError => 'ERR';

  @override
  String get logBadgeVerbose => 'VRB';

  @override
  String get logBadgeNormal => 'LOG';

  @override
  String songsCount(int count) {
    return '$count songs';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String durationOnlyMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String albumSongsAndDuration(int count, String duration) {
    return '$count songs, $duration';
  }

  @override
  String get madeByShort => 'Made by';
}
