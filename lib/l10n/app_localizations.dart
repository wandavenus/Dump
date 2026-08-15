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
  /// **'Browse'**
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

  /// No description provided for @statusNormalize.
  ///
  /// In en, this message translates to:
  /// **'Normalize'**
  String get statusNormalize;

  /// No description provided for @statusBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass Boost'**
  String get statusBassBoost;

  /// No description provided for @statusEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get statusEqualizer;

  /// No description provided for @statusSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get statusSpeed;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @logSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search messages or categories…'**
  String get logSearchHint;

  /// No description provided for @logTitle.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logTitle;

  /// No description provided for @liveLabel.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get liveLabel;

  /// No description provided for @loudnessReplayGainTrack.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain (Track)'**
  String get loudnessReplayGainTrack;

  /// No description provided for @loudnessReplayGainAlbum.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain (Album)'**
  String get loudnessReplayGainAlbum;

  /// No description provided for @loudnessR128Track.
  ///
  /// In en, this message translates to:
  /// **'R128 (Track)'**
  String get loudnessR128Track;

  /// No description provided for @loudnessR128Album.
  ///
  /// In en, this message translates to:
  /// **'R128 (Album)'**
  String get loudnessR128Album;

  /// No description provided for @loudnessITunNorm.
  ///
  /// In en, this message translates to:
  /// **'iTunNORM'**
  String get loudnessITunNorm;

  /// No description provided for @loudnessEmbedded.
  ///
  /// In en, this message translates to:
  /// **'Embedded'**
  String get loudnessEmbedded;

  /// No description provided for @loudnessNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get loudnessNone;

  /// No description provided for @lyricsSourceEmbedded.
  ///
  /// In en, this message translates to:
  /// **'From file tags'**
  String get lyricsSourceEmbedded;

  /// No description provided for @lyricsSourceLocalFile.
  ///
  /// In en, this message translates to:
  /// **'From .lrc file'**
  String get lyricsSourceLocalFile;

  /// No description provided for @lyricsSourceInternet.
  ///
  /// In en, this message translates to:
  /// **'From internet'**
  String get lyricsSourceInternet;

  /// No description provided for @lyricsTypeSynced.
  ///
  /// In en, this message translates to:
  /// **'LRC (synced)'**
  String get lyricsTypeSynced;

  /// No description provided for @lyricsTypePlain.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get lyricsTypePlain;

  /// No description provided for @lyricsQualityWordTimed.
  ///
  /// In en, this message translates to:
  /// **'Word-timed LRC'**
  String get lyricsQualityWordTimed;

  /// No description provided for @lyricsQualityCharTimed.
  ///
  /// In en, this message translates to:
  /// **'Char-timed LRC'**
  String get lyricsQualityCharTimed;

  /// No description provided for @lyricsQualityLineTimed.
  ///
  /// In en, this message translates to:
  /// **'Synced LRC'**
  String get lyricsQualityLineTimed;

  /// No description provided for @lyricsQualityPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain LRC'**
  String get lyricsQualityPlain;

  /// No description provided for @lyricsQualityUnsynced.
  ///
  /// In en, this message translates to:
  /// **'Unsynced'**
  String get lyricsQualityUnsynced;

  /// No description provided for @lyricsQualityNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get lyricsQualityNone;

  /// No description provided for @lyricsColorWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get lyricsColorWhite;

  /// No description provided for @lyricsColorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get lyricsColorRed;

  /// No description provided for @lyricsColorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get lyricsColorYellow;

  /// No description provided for @sleepPresetMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String sleepPresetMinutes(int minutes);

  /// No description provided for @sleepPresetHour.
  ///
  /// In en, this message translates to:
  /// **'{hours} hour'**
  String sleepPresetHour(String hours);

  /// No description provided for @sleepPresetEndOfSong.
  ///
  /// In en, this message translates to:
  /// **'End of song'**
  String get sleepPresetEndOfSong;

  /// No description provided for @sleepPresetSection.
  ///
  /// In en, this message translates to:
  /// **'CHOOSE DURATION'**
  String get sleepPresetSection;

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

  /// No description provided for @scanLibraryConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan Library?'**
  String get scanLibraryConfirmTitle;

  /// No description provided for @scanLibraryConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will scan your library and calculate ReplayGain data for songs that do not have it yet. Continue?'**
  String get scanLibraryConfirmBody;

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

  /// No description provided for @rgRemoveTagsAction.
  ///
  /// In en, this message translates to:
  /// **'Remove ReplayGain Tags'**
  String get rgRemoveTagsAction;

  /// No description provided for @rgRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove ReplayGain Tags?'**
  String get rgRemoveConfirmTitle;

  /// No description provided for @rgRemoveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain/R128 tags will be removed from every song in your library. All other metadata is preserved.'**
  String get rgRemoveConfirmBody;

  /// No description provided for @rgRemoveRunning.
  ///
  /// In en, this message translates to:
  /// **'Removing ReplayGain tags...'**
  String get rgRemoveRunning;

  /// No description provided for @rgRemoveLibrarySuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} songs cleaned'**
  String rgRemoveLibrarySuccess(int count);

  /// No description provided for @rgRemoveLibraryPartial.
  ///
  /// In en, this message translates to:
  /// **'{removed} cleaned, {failed} failed'**
  String rgRemoveLibraryPartial(int removed, int failed);

  /// No description provided for @rgRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove ReplayGain tags'**
  String get rgRemoveFailed;

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
  /// **'Pure Audio'**
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
  /// **'PLAYER'**
  String get sectionBitPerfect;

  /// No description provided for @bitPerfectMode.
  ///
  /// In en, this message translates to:
  /// **'Pure Audio Mode'**
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
  /// **'Activate Pure Audio Mode?'**
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

  /// No description provided for @debugLabel.
  ///
  /// In en, this message translates to:
  /// **'DEBUG'**
  String get debugLabel;

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

  /// No description provided for @qrisSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save QR Code'**
  String get qrisSaveTitle;

  /// No description provided for @qrisSavePrompt.
  ///
  /// In en, this message translates to:
  /// **'Save the QRIS image to your gallery?'**
  String get qrisSavePrompt;

  /// No description provided for @qrisGalleryDenied.
  ///
  /// In en, this message translates to:
  /// **'Gallery permission denied — enable it in Settings › App Permissions'**
  String get qrisGalleryDenied;

  /// No description provided for @qrisSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Image saved to gallery'**
  String get qrisSavedToGallery;

  /// No description provided for @qrisAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Gallery access denied'**
  String get qrisAccessDenied;

  /// No description provided for @qrisNotEnoughSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage space'**
  String get qrisNotEnoughSpace;

  /// No description provided for @qrisFormatUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Format not supported'**
  String get qrisFormatUnsupported;

  /// No description provided for @qrisUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected gallery error'**
  String get qrisUnexpectedError;

  /// No description provided for @qrisSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {reason}'**
  String qrisSaveFailed(String reason);

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

  /// No description provided for @sleepFadingOut.
  ///
  /// In en, this message translates to:
  /// **'Fading out…'**
  String get sleepFadingOut;

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
  /// **'Browse'**
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

  /// No description provided for @noRecentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'No recently played songs'**
  String get noRecentlyPlayed;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String searchNoResults(String query);

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
  /// **'Send your report to'**
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

  /// No description provided for @deletePlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'Playlist \"{name}\" will be permanently deleted.'**
  String deletePlaylistBody(String name);

  /// No description provided for @timerEndOfSong.
  ///
  /// In en, this message translates to:
  /// **'End of song'**
  String get timerEndOfSong;

  /// No description provided for @sectionDetails.
  ///
  /// In en, this message translates to:
  /// **'DETAILS'**
  String get sectionDetails;

  /// No description provided for @sectionAudioQuality.
  ///
  /// In en, this message translates to:
  /// **'AUDIO QUALITY'**
  String get sectionAudioQuality;

  /// No description provided for @sectionLoudness.
  ///
  /// In en, this message translates to:
  /// **'LOUDNESS'**
  String get sectionLoudness;

  /// No description provided for @sectionEmbedded.
  ///
  /// In en, this message translates to:
  /// **'EMBEDDED CONTENT'**
  String get sectionEmbedded;

  /// No description provided for @sectionStatistics.
  ///
  /// In en, this message translates to:
  /// **'STATISTICS'**
  String get sectionStatistics;

  /// No description provided for @sectionFile.
  ///
  /// In en, this message translates to:
  /// **'FILE'**
  String get sectionFile;

  /// No description provided for @sectionAdditionalInfo.
  ///
  /// In en, this message translates to:
  /// **'ADDITIONAL INFO'**
  String get sectionAdditionalInfo;

  /// No description provided for @fieldAlbumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album Artist'**
  String get fieldAlbumArtist;

  /// No description provided for @fieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get fieldGenre;

  /// No description provided for @fieldYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get fieldYear;

  /// No description provided for @fieldTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get fieldTrack;

  /// No description provided for @trackDiscValue.
  ///
  /// In en, this message translates to:
  /// **'{track} (Disc {disc})'**
  String trackDiscValue(String track, String disc);

  /// No description provided for @fieldFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get fieldFormat;

  /// No description provided for @fieldBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit Depth'**
  String get fieldBitDepth;

  /// No description provided for @fieldSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample Rate'**
  String get fieldSampleRate;

  /// No description provided for @fieldChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get fieldChannels;

  /// No description provided for @fieldBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get fieldBitrate;

  /// No description provided for @fieldEncoder.
  ///
  /// In en, this message translates to:
  /// **'Encoder'**
  String get fieldEncoder;

  /// No description provided for @fieldFileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size'**
  String get fieldFileSize;

  /// No description provided for @fieldAppliedGain.
  ///
  /// In en, this message translates to:
  /// **'Applied Gain'**
  String get fieldAppliedGain;

  /// No description provided for @fieldLoudnessSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get fieldLoudnessSource;

  /// No description provided for @fieldLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get fieldLyrics;

  /// No description provided for @fieldPlayCount.
  ///
  /// In en, this message translates to:
  /// **'Play Count'**
  String get fieldPlayCount;

  /// No description provided for @fieldFileName.
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get fieldFileName;

  /// No description provided for @fieldFilePath.
  ///
  /// In en, this message translates to:
  /// **'File Path'**
  String get fieldFilePath;

  /// No description provided for @fieldFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get fieldFolder;

  /// No description provided for @fieldDateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date Added'**
  String get fieldDateAdded;

  /// No description provided for @fieldModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get fieldModified;

  /// No description provided for @fieldComposer.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get fieldComposer;

  /// No description provided for @fieldPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get fieldPublisher;

  /// No description provided for @fieldCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get fieldCopyright;

  /// No description provided for @fieldIsrc.
  ///
  /// In en, this message translates to:
  /// **'ISRC'**
  String get fieldIsrc;

  /// No description provided for @fieldComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get fieldComment;

  /// No description provided for @fieldRgTrackGain.
  ///
  /// In en, this message translates to:
  /// **'RG Track Gain'**
  String get fieldRgTrackGain;

  /// No description provided for @fieldRgTrackPeak.
  ///
  /// In en, this message translates to:
  /// **'RG Track Peak'**
  String get fieldRgTrackPeak;

  /// No description provided for @fieldRgAlbumGain.
  ///
  /// In en, this message translates to:
  /// **'RG Album Gain'**
  String get fieldRgAlbumGain;

  /// No description provided for @fieldRgAlbumPeak.
  ///
  /// In en, this message translates to:
  /// **'RG Album Peak'**
  String get fieldRgAlbumPeak;

  /// No description provided for @fieldR128TrackGain.
  ///
  /// In en, this message translates to:
  /// **'R128 Track Gain'**
  String get fieldR128TrackGain;

  /// No description provided for @fieldR128AlbumGain.
  ///
  /// In en, this message translates to:
  /// **'R128 Album Gain'**
  String get fieldR128AlbumGain;

  /// No description provided for @channelMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get channelMono;

  /// No description provided for @channelStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get channelStereo;

  /// No description provided for @channelQuad.
  ///
  /// In en, this message translates to:
  /// **'Quad'**
  String get channelQuad;

  /// No description provided for @channel51Surround.
  ///
  /// In en, this message translates to:
  /// **'5.1 Surround'**
  String get channel51Surround;

  /// No description provided for @channel71Surround.
  ///
  /// In en, this message translates to:
  /// **'7.1 Surround'**
  String get channel71Surround;

  /// No description provided for @bitrateUnknownLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get bitrateUnknownLossless;

  /// No description provided for @glassToggleNavBar.
  ///
  /// In en, this message translates to:
  /// **'NavBar'**
  String get glassToggleNavBar;

  /// No description provided for @glassToggleAppBar.
  ///
  /// In en, this message translates to:
  /// **'AppBar'**
  String get glassToggleAppBar;

  /// No description provided for @glassToggleMiniPlayer.
  ///
  /// In en, this message translates to:
  /// **'Mini Player'**
  String get glassToggleMiniPlayer;

  /// No description provided for @glassToggleAlbumCard.
  ///
  /// In en, this message translates to:
  /// **'Album Card'**
  String get glassToggleAlbumCard;

  /// No description provided for @logLevelTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Level'**
  String get logLevelTitle;

  /// No description provided for @logLevelOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get logLevelOff;

  /// No description provided for @logLevelOffDesc.
  ///
  /// In en, this message translates to:
  /// **'Logging disabled'**
  String get logLevelOffDesc;

  /// No description provided for @logLevelErrorsOnly.
  ///
  /// In en, this message translates to:
  /// **'Errors & Warnings Only'**
  String get logLevelErrorsOnly;

  /// No description provided for @logLevelErrorsOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide info & verbose logs'**
  String get logLevelErrorsOnlyDesc;

  /// No description provided for @logLevelNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get logLevelNormal;

  /// No description provided for @logLevelNormalDesc.
  ///
  /// In en, this message translates to:
  /// **'Log info, errors & warnings'**
  String get logLevelNormalDesc;

  /// No description provided for @logLevelVerbose.
  ///
  /// In en, this message translates to:
  /// **'Verbose Log'**
  String get logLevelVerbose;

  /// No description provided for @logLevelVerboseDesc.
  ///
  /// In en, this message translates to:
  /// **'Show detailed logs'**
  String get logLevelVerboseDesc;

  /// No description provided for @clearLogsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all logs?'**
  String get clearLogsConfirm;

  /// No description provided for @logScrollTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get logScrollTop;

  /// No description provided for @logScrollBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get logScrollBottom;

  /// No description provided for @logCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get logCopyAll;

  /// No description provided for @logNoResults.
  ///
  /// In en, this message translates to:
  /// **'no results'**
  String get logNoResults;

  /// No description provided for @logEmpty.
  ///
  /// In en, this message translates to:
  /// **'no logs yet'**
  String get logEmpty;

  /// No description provided for @logCopiedEntries.
  ///
  /// In en, this message translates to:
  /// **'{count} entries copied'**
  String logCopiedEntries(int count);

  /// No description provided for @logCopiedEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry copied'**
  String get logCopiedEntry;

  /// No description provided for @songsFoundMsg.
  ///
  /// In en, this message translates to:
  /// **'Found {count} songs'**
  String songsFoundMsg(int count);

  /// No description provided for @rescanSongs.
  ///
  /// In en, this message translates to:
  /// **'Rescan Songs'**
  String get rescanSongs;

  /// No description provided for @cantOpenEmail.
  ///
  /// In en, this message translates to:
  /// **'Cannot open email app'**
  String get cantOpenEmail;

  /// No description provided for @audioEngineInfo.
  ///
  /// In en, this message translates to:
  /// **'Audio Engine Info'**
  String get audioEngineInfo;

  /// No description provided for @activeEffectsStatus.
  ///
  /// In en, this message translates to:
  /// **'Active Effects Status'**
  String get activeEffectsStatus;

  /// No description provided for @weRecommend.
  ///
  /// In en, this message translates to:
  /// **'We Recommend'**
  String get weRecommend;

  /// No description provided for @newMusicSection.
  ///
  /// In en, this message translates to:
  /// **'New Music'**
  String get newMusicSection;

  /// No description provided for @dailyTop100.
  ///
  /// In en, this message translates to:
  /// **'Daily Top 100'**
  String get dailyTop100;

  /// No description provided for @tvAndFilm.
  ///
  /// In en, this message translates to:
  /// **'TV & Film'**
  String get tvAndFilm;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @notSupportedDevice.
  ///
  /// In en, this message translates to:
  /// **'Not supported on this device'**
  String get notSupportedDevice;

  /// No description provided for @hardKnee.
  ///
  /// In en, this message translates to:
  /// **'Hard knee'**
  String get hardKnee;

  /// No description provided for @noPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get noPlaylists;

  /// No description provided for @bugReportParagraph1.
  ///
  /// In en, this message translates to:
  /// **'If you find a bug, error, crash, or something not working as expected, please report it so it can be fixed quickly.'**
  String get bugReportParagraph1;

  /// No description provided for @bugReportParagraph2.
  ///
  /// In en, this message translates to:
  /// **'You can also send suggestions, feedback, or new feature requests. Every report helps improve the app quality.'**
  String get bugReportParagraph2;

  /// No description provided for @speedDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjusts song playback speed. Below 1x slows down, above 1x speeds up, without changing pitch.'**
  String get speedDesc;

  /// No description provided for @pitchDesc.
  ///
  /// In en, this message translates to:
  /// **'Raises or lowers the song pitch in semitones, without changing playback speed.'**
  String get pitchDesc;

  /// No description provided for @bassBoostDesc.
  ///
  /// In en, this message translates to:
  /// **'Boosts bass frequencies for a deeper, thicker low-end sound. Higher percentage = stronger effect.'**
  String get bassBoostDesc;

  /// No description provided for @preampDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjusts the base volume before EQ and other effects are processed. Slide right to raise, left to lower.'**
  String get preampDesc;

  /// No description provided for @compressorDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduces the volume difference between quiet and loud sounds. Higher ratio = more aggressive compression. 1:1 means off.'**
  String get compressorDesc;

  /// No description provided for @compressorThresholdTitle.
  ///
  /// In en, this message translates to:
  /// **'Compressor Threshold'**
  String get compressorThresholdTitle;

  /// No description provided for @compressorThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'The volume level where compression kicks in. Lower value = more audio compressed.'**
  String get compressorThresholdDesc;

  /// No description provided for @compressorAttackTitle.
  ///
  /// In en, this message translates to:
  /// **'Compressor Attack'**
  String get compressorAttackTitle;

  /// No description provided for @compressorAttackDesc.
  ///
  /// In en, this message translates to:
  /// **'How quickly the compressor reacts when audio exceeds the threshold. Faster = more responsive to sudden sounds.'**
  String get compressorAttackDesc;

  /// No description provided for @compressorReleaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Compressor Release'**
  String get compressorReleaseTitle;

  /// No description provided for @compressorReleaseDesc.
  ///
  /// In en, this message translates to:
  /// **'How quickly volume returns to normal after compression. Too fast can sound \'pumpy\'.'**
  String get compressorReleaseDesc;

  /// No description provided for @compressorKneeTitle.
  ///
  /// In en, this message translates to:
  /// **'Compressor Knee'**
  String get compressorKneeTitle;

  /// No description provided for @compressorKneeDesc.
  ///
  /// In en, this message translates to:
  /// **'Softens the transition into compression around the threshold. 0 dB = hard knee.'**
  String get compressorKneeDesc;

  /// No description provided for @limiterDesc.
  ///
  /// In en, this message translates to:
  /// **'Prevents audio from exceeding a set volume level to avoid clipping/distortion. Slide below 0 dB to activate.'**
  String get limiterDesc;

  /// No description provided for @limiterReleaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Limiter Release'**
  String get limiterReleaseTitle;

  /// No description provided for @limiterReleaseDesc.
  ///
  /// In en, this message translates to:
  /// **'How quickly the limiter releases after capping a peak. Too fast can sound unnatural.'**
  String get limiterReleaseDesc;

  /// No description provided for @softClipperDesc.
  ///
  /// In en, this message translates to:
  /// **'Gently rounds off excessively loud peaks as a final safety layer before output, making distortion less noticeable than a limiter.'**
  String get softClipperDesc;

  /// No description provided for @dspPipeline.
  ///
  /// In en, this message translates to:
  /// **'DSP Pipeline'**
  String get dspPipeline;

  /// No description provided for @androidDsp.
  ///
  /// In en, this message translates to:
  /// **'Android DSP'**
  String get androidDsp;

  /// No description provided for @webFallback.
  ///
  /// In en, this message translates to:
  /// **'Web / Fallback'**
  String get webFallback;

  /// No description provided for @supported.
  ///
  /// In en, this message translates to:
  /// **'Supported ✓'**
  String get supported;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable ✗'**
  String get unavailable;

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String durationSeconds(int seconds);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String durationMinutesSeconds(int minutes, int seconds);

  /// No description provided for @durationHoursMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m {seconds}s'**
  String durationHoursMinutesSeconds(int hours, int minutes, int seconds);

  /// No description provided for @lyricsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Lyrics not found'**
  String get lyricsNotFound;

  /// No description provided for @lyricsFileHint.
  ///
  /// In en, this message translates to:
  /// **'Add an .lrc file in the same folder as the song, or configure the lyrics folder in Settings.'**
  String get lyricsFileHint;

  /// No description provided for @noSongSelected.
  ///
  /// In en, this message translates to:
  /// **'No song selected'**
  String get noSongSelected;

  /// No description provided for @lockedInactive.
  ///
  /// In en, this message translates to:
  /// **'Controls locked — Bit-Perfect Mode is active'**
  String get lockedInactive;

  /// No description provided for @bandEq.
  ///
  /// In en, this message translates to:
  /// **'BAND EQ'**
  String get bandEq;

  /// No description provided for @preset.
  ///
  /// In en, this message translates to:
  /// **'PRESET'**
  String get preset;

  /// No description provided for @pitchSemitone.
  ///
  /// In en, this message translates to:
  /// **'{value} semitone'**
  String pitchSemitone(String value);

  /// No description provided for @decibelValue.
  ///
  /// In en, this message translates to:
  /// **'{value} dB'**
  String decibelValue(String value);

  /// No description provided for @millisecondsValue.
  ///
  /// In en, this message translates to:
  /// **'{value} ms'**
  String millisecondsValue(String value);

  /// No description provided for @crossfadeOptionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get crossfadeOptionOff;

  /// No description provided for @crossfadeOptionSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String crossfadeOptionSeconds(String seconds);

  /// No description provided for @listenAgain.
  ///
  /// In en, this message translates to:
  /// **'Listen Again'**
  String get listenAgain;

  /// No description provided for @moreFromArtist.
  ///
  /// In en, this message translates to:
  /// **'More from {artist}'**
  String moreFromArtist(String artist);

  /// No description provided for @topPicks.
  ///
  /// In en, this message translates to:
  /// **'Top Picks For You'**
  String get topPicks;

  /// No description provided for @songsByArtist.
  ///
  /// In en, this message translates to:
  /// **'{songs} songs • {albums} albums'**
  String songsByArtist(int songs, int albums);

  /// No description provided for @lossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get lossless;

  /// No description provided for @contentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No content yet'**
  String get contentUnavailable;

  /// No description provided for @playedCount.
  ///
  /// In en, this message translates to:
  /// **'Played {count}x'**
  String playedCount(int count);

  /// No description provided for @copyrightFooter.
  ///
  /// In en, this message translates to:
  /// **'© {year} Flutter Music App with Media3 ExoPlayer'**
  String copyrightFooter(int year);

  /// No description provided for @logFilterAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get logFilterAll;

  /// No description provided for @logFilterError.
  ///
  /// In en, this message translates to:
  /// **'ERR'**
  String get logFilterError;

  /// No description provided for @logFilterWarning.
  ///
  /// In en, this message translates to:
  /// **'WRN'**
  String get logFilterWarning;

  /// No description provided for @logFilterInfo.
  ///
  /// In en, this message translates to:
  /// **'INF'**
  String get logFilterInfo;

  /// No description provided for @logFilterVerbose.
  ///
  /// In en, this message translates to:
  /// **'VRB'**
  String get logFilterVerbose;

  /// No description provided for @logBadgeOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get logBadgeOff;

  /// No description provided for @logBadgeError.
  ///
  /// In en, this message translates to:
  /// **'ERR'**
  String get logBadgeError;

  /// No description provided for @logBadgeVerbose.
  ///
  /// In en, this message translates to:
  /// **'VRB'**
  String get logBadgeVerbose;

  /// No description provided for @logBadgeNormal.
  ///
  /// In en, this message translates to:
  /// **'LOG'**
  String get logBadgeNormal;

  /// No description provided for @songsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String songsCount(int count);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr {minutes} min'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationOnlyMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationOnlyMinutes(int minutes);

  /// No description provided for @albumSongsAndDuration.
  ///
  /// In en, this message translates to:
  /// **'{count} songs, {duration}'**
  String albumSongsAndDuration(int count, String duration);

  /// No description provided for @madeByShort.
  ///
  /// In en, this message translates to:
  /// **'Made by'**
  String get madeByShort;
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
