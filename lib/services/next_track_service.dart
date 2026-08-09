import 'dart:async';

import '../models/local_song.dart';
import 'audio/playback_manager.dart';
import 'audio_service.dart';
import 'log_service.dart';

/// Handles the "Putar Selanjutnya" action without letting shuffle steal the slot.
///
/// When shuffle is enabled, the queued-next song is inserted with shuffle
/// temporarily disabled. Shuffle is restored after the requested song becomes
/// the current track, so only the one next transition is forced linear.
class NextTrackService {
  NextTrackService._();

  static StreamSubscription<Map<dynamic, dynamic>?>? _trackSub;
  static Timer? _restoreTimer;
  static int? _pendingSongId;
  static bool _shouldRestoreShuffle = false;

  static Future<void> playNext(LocalSong song) async {
    final restoreShuffle = AudioService.shuffleEnabled;
    _resetWatchers();

    _pendingSongId = song.id;
    _shouldRestoreShuffle = restoreShuffle;

    if (restoreShuffle) {
      await PlaybackManager.setShuffleMode(false);
      LogService.log(
        'AudioService',
        'Play Next: temporary shuffle bypass enabled',
      );
    }

    AudioService.addToQueueNext(song);

    if (!restoreShuffle) return;

    _trackSub = PlaybackManager.currentTrackStream.listen((track) {
      final currentId = _extractSongId(track);
      if (currentId != null && currentId == _pendingSongId) {
        unawaited(_restoreShuffleOnce());
      }
    });

    // Fail-safe: restore shuffle even if the queued song never starts.
    _restoreTimer = Timer(const Duration(minutes: 10), () {
      unawaited(_restoreShuffleOnce());
    });
  }

  static int? _extractSongId(Map<dynamic, dynamic>? track) {
    if (track == null) return null;
    final raw = track['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static Future<void> _restoreShuffleOnce() async {
    if (!_shouldRestoreShuffle) {
      _resetWatchers();
      return;
    }

    _resetWatchers();

    try {
      await PlaybackManager.setShuffleMode(true);
      LogService.log(
        'AudioService',
        'Play Next: shuffle restored after requested track started',
      );
    } on Exception catch (e) {
      LogService.warn(
        'AudioService',
        'Play Next: failed to restore shuffle: $e',
      );
    }
  }

  static void _resetWatchers() {
    _trackSub?.cancel();
    _trackSub = null;
    _restoreTimer?.cancel();
    _restoreTimer = null;
    _pendingSongId = null;
    _shouldRestoreShuffle = false;
  }
}
