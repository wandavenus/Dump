import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// App name
  ///
  /// In en, this message translates to:
  /// **'Music Player'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get navBrowse;

  /// No description provided for @navRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get navRadio;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get disabled;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @testNow.
  ///
  /// In en, this message translates to:
  /// **'Test Now'**
  String get testNow;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get sectionAppearance;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get themeAutomatic;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @showUpNext.
  ///
  /// In en, this message translates to:
  /// **'Show Up Next'**
  String get showUpNext;

  /// No description provided for @showUpNextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Next song card in player'**
  String get showUpNextSubtitle;

  /// No description provided for @liquidGlass.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass'**
  String get liquidGlass;

  /// No description provided for @liquidGlassSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Transparent blur effect on the entire UI'**
  String get liquidGlassSubtitle;

  /// No description provided for @sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get sectionLanguage;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageIndonesian.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Indonesia'**
  String get languageIndonesian;

  /// No description provided for @sectionAudio.
  ///
  /// In en, this message translates to:
  /// **'AUDIO'**
  String get sectionAudio;

  /// No description provided for @audioNormalize.
  ///
  /// In en, this message translates to:
  /// **'Audio Normalize'**
  String get audioNormalize;

  /// No description provided for @modeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get modeLabel;

  /// No description provided for @crossfeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Crossfeed'**
  String get crossfeedTitle;

  /// No description provided for @crossfeedActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Simulates speaker-like channel blending for headphones'**
  String get crossfeedActiveSubtitle;

  /// No description provided for @crossfeedInactiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable for more natural headphone listening'**
  String get crossfeedInactiveSubtitle;

  /// No description provided for @crossfeedStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get crossfeedStrength;

  /// No description provided for @crossfadeTitle.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get crossfadeTitle;

  /// No description provided for @crossfadeSeconds.
  ///
  /// In en, this message translates to:
  /// **'{secs} seconds'**
  String crossfadeSeconds(String secs);

  /// No description provided for @stereoWidening.
  ///
  /// In en, this message translates to:
  /// **'Stereo Widening'**
  String get stereoWidening;

  /// No description provided for @loudnessNormalization.
  ///
  /// In en, this message translates to:
  /// **'Loudness Normalization'**
  String get loudnessNormalization;

  /// No description provided for @loudnessNormActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Equalizes loudness in real-time (EBU R128)'**
  String get loudnessNormActiveSubtitle;

  /// No description provided for @loudnessNormInactiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Normalize loudness during playback'**
  String get loudnessNormInactiveSubtitle;

  /// No description provided for @loudnessTarget.
  ///
  /// In en, this message translates to:
  /// **'Target: {value} LUFS'**
  String loudnessTarget(String value);

  /// No description provided for @loudnessHint.
  ///
  /// In en, this message translates to:
  /// **'Streaming −14, Podcast −16, Broadcast −23'**
  String get loudnessHint;

  /// No description provided for @preamp.
  ///
  /// In en, this message translates to:
  /// **'Preamp'**
  String get preamp;

  /// No description provided for @clippingProtection.
  ///
  /// In en, this message translates to:
  /// **'Clipping Protection'**
  String get clippingProtection;

  /// No description provided for @clippingProtectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent distortion when gain exceeds 0 dBFS'**
  String get clippingProtectionSubtitle;

  /// No description provided for @replayGainTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio Normalize'**
  String get replayGainTitle;

  /// No description provided for @replayGainModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get replayGainModeLabel;

  /// No description provided for @replayGainPreampLabel.
  ///
  /// In en, this message translates to:
  /// **'Preamp'**
  String get replayGainPreampLabel;

  /// No description provided for @replayGainOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get replayGainOff;

  /// No description provided for @replayGainAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get replayGainAuto;

  /// No description provided for @replayGainTrack.
  ///
  /// In en, this message translates to:
  /// **'Track Gain'**
  String get replayGainTrack;

  /// No description provided for @replayGainAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album Gain'**
  String get replayGainAlbum;

  /// No description provided for @replayGainOffDesc.
  ///
  /// In en, this message translates to:
  /// **'No volume normalization'**
  String get replayGainOffDesc;

  /// No description provided for @replayGainAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the best available loudness source'**
  String get replayGainAutoDesc;

  /// No description provided for @replayGainTrackDesc.
  ///
  /// In en, this message translates to:
  /// **'Normalize each song independently'**
  String get replayGainTrackDesc;

  /// No description provided for @replayGainAlbumDesc.
  ///
  /// In en, this message translates to:
  /// **'Maintain volume relationship between songs in an album'**
  String get replayGainAlbumDesc;

  /// No description provided for @scanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Scan Library'**
  String get scanLibrary;

  /// No description provided for @scanLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Calculate ReplayGain for songs without data'**
  String get scanLibrarySubtitle;

  /// No description provided for @scanPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get scanPreparing;

  /// No description provided for @noSongsInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No songs found in library.'**
  String get noSongsInLibrary;

  /// No description provided for @scanLibraryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load library: {error}'**
  String scanLibraryLoadFailed(String error);

  /// No description provided for @scanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled · {count} songs succeeded'**
  String scanCancelled(int count);

  /// No description provided for @scanSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} songs scanned successfully'**
  String scanSuccess(int count);

  /// No description provided for @scanPartial.
  ///
  /// In en, this message translates to:
  /// **'{succeeded} succeeded, {failed} failed'**
  String scanPartial(int succeeded, int failed);

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to scan songs'**
  String get scanFailed;

  /// No description provided for @sectionEqualizer.
  ///
  /// In en, this message translates to:
  /// **'EQUALIZER'**
  String get sectionEqualizer;

  /// No description provided for @equalizerTitle.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizerTitle;

  /// No description provided for @equalizerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get equalizerCustom;

  /// No description provided for @equalizerBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect'**
  String get equalizerBitPerfect;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playbackSpeed;

  /// No description provided for @pitchShift.
  ///
  /// In en, this message translates to:
  /// **'Pitch Shift'**
  String get pitchShift;

  /// No description provided for @bassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass Boost'**
  String get bassBoost;

  /// No description provided for @compressor.
  ///
  /// In en, this message translates to:
  /// **'Compressor'**
  String get compressor;

  /// No description provided for @limiter.
  ///
  /// In en, this message translates to:
  /// **'Limiter'**
  String get limiter;

  /// No description provided for @softClipper.
  ///
  /// In en, this message translates to:
  /// **'Soft Clipper'**
  String get softClipper;

  /// No description provided for @sectionBitPerfect.
  ///
  /// In en, this message translates to:
  /// **'BIT-PERFECT'**
  String get sectionBitPerfect;

  /// No description provided for @bitPerfectMode.
  ///
  /// In en, this message translates to:
  /// **'Bit-Perfect Mode'**
  String get bitPerfectMode;

  /// No description provided for @bitPerfectActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Active — all audio processing disabled'**
  String get bitPerfectActiveSubtitle;

  /// No description provided for @bitPerfectInactiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disable all effects & audio processing'**
  String get bitPerfectInactiveSubtitle;

  /// No description provided for @bitPerfectDescription.
  ///
  /// In en, this message translates to:
  /// **'All effects and audio processing throughout the app will be forcibly disabled. Active settings will be saved and automatically restored when this mode is turned off.'**
  String get bitPerfectDescription;

  /// No description provided for @bitPerfectConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate Bit-Perfect Mode?'**
  String get bitPerfectConfirmTitle;

  /// No description provided for @bitPerfectConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All effects and audio processing throughout the app will be forcibly disabled. Active settings will be saved and automatically restored when this mode is turned off.'**
  String get bitPerfectConfirmBody;

  /// No description provided for @sectionSystem.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get sectionSystem;

  /// No description provided for @activityLog.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get activityLog;

  /// No description provided for @logEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String logEntryCount(int count);

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get sectionAbout;

  /// No description provided for @reportBug.
  ///
  /// In en, this message translates to:
  /// **'Report Bug'**
  String get reportBug;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @changelogTitle.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelogTitle;

  /// No description provided for @noChangelog.
  ///
  /// In en, this message translates to:
  /// **'No changes recorded yet'**
  String get noChangelog;

  /// No description provided for @debugSection.
  ///
  /// In en, this message translates to:
  /// **'MODE ACTIVE'**
  String get debugSection;

  /// No description provided for @sessionStats.
  ///
  /// In en, this message translates to:
  /// **'Session Statistics'**
  String get sessionStats;

  /// No description provided for @exitDebugMode.
  ///
  /// In en, this message translates to:
  /// **'Exit Debug Mode'**
  String get exitDebugMode;

  /// No description provided for @checkAAudio.
  ///
  /// In en, this message translates to:
  /// **'Check AAudio Exclusive/MMAP'**
  String get checkAAudio;

  /// No description provided for @aaudioNotTested.
  ///
  /// In en, this message translates to:
  /// **'Not tested — open a real stream to see the mode actually granted by the OS'**
  String get aaudioNotTested;

  /// No description provided for @aaudioNotAvailablePlatform.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get aaudioNotAvailablePlatform;

  /// No description provided for @aaudioNotAvailableAndroid.
  ///
  /// In en, this message translates to:
  /// **'AAudio not available (Android < 8.1)'**
  String get aaudioNotAvailableAndroid;

  /// No description provided for @aaudioTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to test AAudio'**
  String get aaudioTestFailed;

  /// No description provided for @debugModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Debug mode enabled'**
  String get debugModeEnabled;

  /// No description provided for @cantOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Cannot open link'**
  String get cantOpenLink;

  /// No description provided for @sleepTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimerTitle;

  /// No description provided for @cancelTimer.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelTimer;

  /// No description provided for @sleepTimerActive.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer Active'**
  String get sleepTimerActive;

  /// No description provided for @sleepAfterSong.
  ///
  /// In en, this message translates to:
  /// **'Stop after this song ends'**
  String get sleepAfterSong;

  /// No description provided for @sleepFadeOut.
  ///
  /// In en, this message translates to:
  /// **'Music will fade out slowly when the timer ends'**
  String get sleepFadeOut;

  /// No description provided for @timerAfterSong.
  ///
  /// In en, this message translates to:
  /// **'Timer: stop after this song'**
  String get timerAfterSong;

  /// No description provided for @timerDuration.
  ///
  /// In en, this message translates to:
  /// **'Timer: {label}'**
  String timerDuration(String label);

  /// No description provided for @upNextLabel.
  ///
  /// In en, this message translates to:
  /// **'UP NEXT'**
  String get upNextLabel;

  /// No description provided for @shuffleOn.
  ///
  /// In en, this message translates to:
  /// **'Shuffle On'**
  String get shuffleOn;

  /// No description provided for @shuffleOff.
  ///
  /// In en, this message translates to:
  /// **'Shuffle Off'**
  String get shuffleOff;

  /// No description provided for @loopOff.
  ///
  /// In en, this message translates to:
  /// **'Loop Off'**
  String get loopOff;

  /// No description provided for @loopAll.
  ///
  /// In en, this message translates to:
  /// **'Loop All'**
  String get loopAll;

  /// No description provided for @loopOne.
  ///
  /// In en, this message translates to:
  /// **'Loop One'**
  String get loopOne;

  /// No description provided for @songInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Song Info'**
  String get songInfoLabel;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get queueEmpty;

  /// No description provided for @continuePlaying.
  ///
  /// In en, this message translates to:
  /// **'Continue Playing'**
  String get continuePlaying;

  /// No description provided for @autoplayDescription.
  ///
  /// In en, this message translates to:
  /// **'Auto-playing similar music'**
  String get autoplayDescription;

  /// No description provided for @lyricsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Appearance'**
  String get lyricsAppearance;

  /// No description provided for @textSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get textSizeLabel;

  /// No description provided for @textAlignLabel.
  ///
  /// In en, this message translates to:
  /// **'Text Alignment'**
  String get textAlignLabel;

  /// No description provided for @activeColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Active Color'**
  String get activeColorLabel;

  /// No description provided for @karaokeHighlight.
  ///
  /// In en, this message translates to:
  /// **'Karaoke Highlight'**
  String get karaokeHighlight;

  /// No description provided for @karaokeHighlightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Character-by-character animation'**
  String get karaokeHighlightSubtitle;

  /// No description provided for @showLyricsSource.
  ///
  /// In en, this message translates to:
  /// **'Show Lyrics Source'**
  String get showLyricsSource;

  /// No description provided for @playNow.
  ///
  /// In en, this message translates to:
  /// **'Play Now'**
  String get playNow;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play Next'**
  String get playNext;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to Queue'**
  String get addToQueue;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get addToFavorites;

  /// No description provided for @addToPlaylistMenu.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get addToPlaylistMenu;

  /// No description provided for @openAlbum.
  ///
  /// In en, this message translates to:
  /// **'Open Album'**
  String get openAlbum;

  /// No description provided for @openArtist.
  ///
  /// In en, this message translates to:
  /// **'Open Artist'**
  String get openArtist;

  /// No description provided for @songInformation.
  ///
  /// In en, this message translates to:
  /// **'Song Information'**
  String get songInformation;

  /// No description provided for @deleteFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Delete from Device'**
  String get deleteFromDevice;

  /// No description provided for @songDeletedMsg.
  ///
  /// In en, this message translates to:
  /// **'Song deleted successfully'**
  String get songDeletedMsg;

  /// No description provided for @songDeleteFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete song'**
  String get songDeleteFailedMsg;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get fieldArtist;

  /// No description provided for @fieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get fieldAlbum;

  /// No description provided for @fieldDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get fieldDuration;

  /// No description provided for @addToPlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get addToPlaylistTitle;

  /// No description provided for @createNewPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create New Playlist'**
  String get createNewPlaylist;

  /// No description provided for @noPlaylistsYet.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get noPlaylistsYet;

  /// No description provided for @addedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added to {name}'**
  String addedToPlaylist(String name);

  /// No description provided for @newPlaylistDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get newPlaylistDialogTitle;

  /// No description provided for @playlistNameHint.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistNameHint;

  /// No description provided for @songCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String songCount(int count);

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renamePlaylist;

  /// No description provided for @deletePlaylistConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist?'**
  String get deletePlaylistConfirm;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get deletePlaylist;

  /// No description provided for @radioTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radioTitle;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently Played'**
  String get recentlyPlayed;

  /// No description provided for @noSongsYet.
  ///
  /// In en, this message translates to:
  /// **'No songs yet'**
  String get noSongsYet;

  /// No description provided for @myPlaylists.
  ///
  /// In en, this message translates to:
  /// **'My Playlists'**
  String get myPlaylists;

  /// No description provided for @noPlaylistsCreated.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get noPlaylistsCreated;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get newPlaylist;

  /// No description provided for @favoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesLabel;

  /// No description provided for @lastPlayedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Played'**
  String get lastPlayedLabel;

  /// No description provided for @mostPlayedLabel.
  ///
  /// In en, this message translates to:
  /// **'Most Played'**
  String get mostPlayedLabel;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @searchInPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Search in Playlists'**
  String get searchInPlaylists;

  /// No description provided for @searchArtists.
  ///
  /// In en, this message translates to:
  /// **'Search Artists'**
  String get searchArtists;

  /// No description provided for @searchAlbums.
  ///
  /// In en, this message translates to:
  /// **'Search Albums'**
  String get searchAlbums;

  /// No description provided for @searchSongs.
  ///
  /// In en, this message translates to:
  /// **'Search Songs'**
  String get searchSongs;

  /// No description provided for @noLocalSongs.
  ///
  /// In en, this message translates to:
  /// **'No local songs found'**
  String get noLocalSongs;

  /// No description provided for @noSongsInList.
  ///
  /// In en, this message translates to:
  /// **'No songs yet'**
  String get noSongsInList;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Artists, Songs, Albums, and more'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String noResults(String query);

  /// No description provided for @browseTitle.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get browseTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @noRecentSongs.
  ///
  /// In en, this message translates to:
  /// **'No songs played yet'**
  String get noRecentSongs;

  /// No description provided for @noArtistsFound.
  ///
  /// In en, this message translates to:
  /// **'No artists found'**
  String get noArtistsFound;

  /// No description provided for @favoriteArtists.
  ///
  /// In en, this message translates to:
  /// **'Favorite Artists'**
  String get favoriteArtists;

  /// No description provided for @topSongs.
  ///
  /// In en, this message translates to:
  /// **'Top Songs'**
  String get topSongs;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get playAll;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutTitle;

  /// No description provided for @musicPlayerName.
  ///
  /// In en, this message translates to:
  /// **'Music Player'**
  String get musicPlayerName;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @debugModeActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Debug Mode Active'**
  String get debugModeActiveLabel;

  /// No description provided for @madeBy.
  ///
  /// In en, this message translates to:
  /// **'Made with dedication by'**
  String get madeBy;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Offline music player based on Flutter with Native Media3 Dual Exoplayer + Single Exoplayer Audio system.'**
  String get appDescription;

  /// No description provided for @releaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Release Notes'**
  String get releaseNotes;

  /// No description provided for @bugReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report Bug'**
  String get bugReportTitle;

  /// No description provided for @thankYouSupport.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your support.'**
  String get thankYouSupport;

  /// No description provided for @sendReportGmail.
  ///
  /// In en, this message translates to:
  /// **'Send your report to Gmail'**
  String get sendReportGmail;

  /// No description provided for @orSocialMedia.
  ///
  /// In en, this message translates to:
  /// **'or to the social media accounts on the About page.'**
  String get orSocialMedia;

  /// No description provided for @playbackStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Playback Session Statistics'**
  String get playbackStatsTitle;

  /// No description provided for @playbackStatsEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine: Native Media3'**
  String get playbackStatsEngine;

  /// No description provided for @playTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Play Time'**
  String get playTimeLabel;

  /// No description provided for @bufferingTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Buffering Time'**
  String get bufferingTimeLabel;

  /// No description provided for @rebufferLabel.
  ///
  /// In en, this message translates to:
  /// **'Rebuffer'**
  String get rebufferLabel;

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorLabel;

  /// No description provided for @statsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Data not available — start playback first.'**
  String get statsNotAvailable;

  /// No description provided for @timesUnit.
  ///
  /// In en, this message translates to:
  /// **'times'**
  String get timesUnit;

  /// No description provided for @secondsZero.
  ///
  /// In en, this message translates to:
  /// **'0 sec'**
  String get secondsZero;

  /// No description provided for @goToSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get goToSettings;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
