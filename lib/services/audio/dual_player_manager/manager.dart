import '../../log_service.dart';
import '../../../models/local_song.dart';

/// Media3-backed player stub — real playback is owned by the native service.
///
/// The previous implementation used two Flutter-side just_audio players.
/// Media3 owns the real native queue now, so this class keeps the public
/// contract used by the rest of the app while routing playback to one
/// native ExoPlayer instance.
class DualPlayerManager {
  DualPlayerManager._();

  static void Function()? onPrimaryChanged;
  static void Function(int sessionId)? onSecondarySessionId;
  static void Function(bool fromCrossfade)? onPromoted;
  static void Function()? onBeforePromote;
  static void Function()? onAfterPromote;

  static bool _initialized = false;
  static LocalSong? _preloadedSong;

  static LocalSong? get preloadedSong => _preloadedSong;

  static Future<void> initialize() async {
    if (_initialized) return;
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
    _preloadedSong = null;
    _initialized = false;
  }
}
