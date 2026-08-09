import 'dart:async';

import '../models/local_song.dart';
import 'audio/playback_manager.dart';
import 'audio_service.dart';
import 'log_service.dart';

/// One-shot helper for the "Putar Selanjutnya" menu action.
///
/// When shuffle is enabled, shuffle is turned off only until the current song
/// changes, so the queued-next song gets exactly one linear turn. After that,
/// shuffle is restored automatically.
class NextTrackService {
  NextTrackService._();

  static StreamSubscription<Map<dynamic, dynamic>?>? _trackSub;
  static Timer? _restoreTimer;
  static int? _sourceSongId;
  static bool _restoreShuffle = false;

  static Future<void> playNext(LocalSong song) async {
    final wasShuffleEnabled = AudioService.shuffleEnabled;
    final sourceSongId = AudioService.currentSong?.id;

    _reset();

    if (wasShuffleEnabled && sourceSongId != null) {
      _sourceSongId = sourceSongId;
      _restoreShuffle = true;

      await PlaybackManager.setShuffleMode(false);
      LogService.log(
        'AudioService',
        'Play Next: temporary shuffle bypass enabled',
      );

      _trackSub = PlaybackManager.currentTrackStream.listen((track) {
        final currentId = _extractSongId(track);
        if (currentId != null && currentId != _sourceSongId) {
          unawaited(_restoreShuffleOnce());
        }
      });

      // Fail-safe: restore shuffle even if playback is interrupted and the
      // queued song never becomes the current track.
      _restoreTimer = Timer(const Duration(minutes: 10), () {
        unawaited(_restoreShuffleOnce());
      });
    }

    AudioService.addToQueueNext(song);
  }

  static int? _extractSongId(Map<dynamic, dynamic>? track) {
    if (track == null) return null;
    final raw = track['id'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static Future<void> _restoreShuffleOnce() async {
    if (!_restoreShuffle) {
      _reset();
      return;
    }

    _reset();

    try {
      await PlaybackManager.setShuffleMode(true);
      LogService.log(
        'AudioService',
        'Play Next: shuffle restored after the queued track started',
      );
    } on Exception catch (e) {
      LogService.warn(
        'AudioService',
        'Play Next: failed to restore shuffle: $e',
      );
    }
  }

  static void _reset() {
    _trackSub?.cancel();
    _trackSub = null;
    _restoreTimer?.cancel();
    _restoreTimer = null;
    _sourceSongId = null;
    _restoreShuffle = false;
  }
}
