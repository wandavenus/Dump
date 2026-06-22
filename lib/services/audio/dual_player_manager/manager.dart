part of '../dual_player_manager.dart';

/// Media3-backed player owner.
///
/// The previous implementation used two Flutter-side players players. Media3 owns the
/// real native queue now, so this class keeps the public contract used by the
/// rest of the app while routing playback to one native ExoPlayer instance.
class DualPlayerManager {
  DualPlayerManager._();

  static void Function()? onPrimaryChanged;
  static void Function(int sessionId)? onSecondarySessionId;
  static void Function(bool fromCrossfade)? onPromoted;
  static void Function()? onBeforePromote;
  static void Function()? onAfterPromote;

  static AudioPlayer? _primary;
  static final AndroidEqualizer _primaryEq = AndroidEqualizer();
  static final AndroidLoudnessEnhancer _primaryLe = AndroidLoudnessEnhancer();
  static bool _initialized = false;
  static LocalSong? _preloadedSong;

  static AudioPlayer get primaryPlayer {
    assert(_initialized, 'DualPlayerManager not initialized');
    return _primary!;
  }

  static AudioPlayer? get secondaryPlayer => null;
  static LocalSong? get preloadedSong => _preloadedSong;
  static AndroidEqualizer? get primaryEqualizer => _primaryEq;
  static AndroidLoudnessEnhancer? get primaryLoudness => _primaryLe;

  static Future<void> initialize() async {
    if (_initialized) return;
    _primary = AudioPlayer();
    _initialized = true;
    onPrimaryChanged?.call();
    LogService.log('Media3Player', 'Native Media3 player connected');
  }

  static Future<void> preloadTrack(LocalSong song) async {
    _preloadedSong = song;
    LogService.verbose(
      'Media3Player',
      'Queued for native gapless: "${song.title}"',
    );
  }

  static Future<void> cancelPreload() async {
    _preloadedSong = null;
  }

  static Future<void> promote({required bool fromCrossfade}) async {
    onBeforePromote?.call();
    onPromoted?.call(fromCrossfade);
    onAfterPromote?.call();
  }

  static Future<void> dispose() async {
    await _primary?.dispose();
    _primary = null;
    _preloadedSong = null;
    _initialized = false;
  }
}
