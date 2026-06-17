import '../models/local_song.dart';
import '../models/loudness_data.dart';
import '../models/replay_gain_mode.dart';
import 'log_service.dart';
import 'replay_gain_service.dart';

/// Branching loudness source selection.
///
/// Given a [ReplayGainMode] and a [LocalSong], resolves the best
/// [LoudnessData] to apply using the following priority:
///
///   Off   → always [LoudnessData.none]
///   Track → track-level RG/R128/iTunNORM tags
///   Album → album-level tags, fallback to track-level
///   Auto  → album gain when consecutive same-album, else track-level
class LoudnessSourceResolver {
  LoudnessSourceResolver._();

  /// Resolves gain for [song] in [mode].
  ///
  /// [previousSong] is used in [ReplayGainMode.auto] to decide whether
  /// to prefer album gain (same album as previous).
  static Future<LoudnessData> resolve({
    required LocalSong song,
    required ReplayGainMode mode,
    LocalSong? previousSong,
  }) async {
    if (mode == ReplayGainMode.off) return const LoudnessData.none();

    final (track, album) = await ReplayGainService.resolveBoth(song);

    final result = switch (mode) {
      ReplayGainMode.off   => const LoudnessData.none(),
      ReplayGainMode.track => track,
      ReplayGainMode.album => album.hasData ? album : track,
      ReplayGainMode.auto  => _auto(
          track:        track,
          album:        album,
          song:         song,
          previousSong: previousSong,
        ),
    };

    if (result.hasData) {
      LogService.verbose(
        'LoudnessResolver',
        '"${song.title}": ${result.gainDb.toStringAsFixed(2)} dB '
        '(${result.source.label}, mode=${mode.name})',
      );
    }

    return result;
  }

  // ── Auto mode ──────────────────────────────────────────────────────────────

  static LoudnessData _auto({
    required LoudnessData track,
    required LoudnessData album,
    required LocalSong song,
    LocalSong? previousSong,
  }) {
    // Use album gain when playing consecutive tracks from the same album.
    if (album.hasData &&
        previousSong != null &&
        _sameAlbum(song, previousSong)) {
      return album;
    }
    // Otherwise prefer track gain for independent normalization.
    if (track.hasData) return track;
    if (album.hasData) return album;
    return const LoudnessData.none();
  }

  static bool _sameAlbum(LocalSong a, LocalSong b) {
    if (a.albumId > 0 && b.albumId > 0) return a.albumId == b.albumId;
    return a.album.trim().toLowerCase() == b.album.trim().toLowerCase() &&
        a.artist.trim().toLowerCase() == b.artist.trim().toLowerCase();
  }
}
