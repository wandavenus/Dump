part of '../replay_gain_service.dart';

/// Reads ReplayGain / R128 / iTunNORM loudness tags from audio file metadata.
///
/// Source priority per track:
///   1. REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_ALBUM_GAIN  (ID3 / Vorbis / APEv2)
///   2. R128_TRACK_GAIN / R128_ALBUM_GAIN              (Opus / FLAC)
///   3. iTunNORM                                       (M4A / AAC)
///   4. No data → [LoudnessData.none]
///
/// Results are cached in SharedPreferences to avoid re-reading tags on
/// every playback.  Cache key format: `rg_SONGID`.
class ReplayGainService {
  ReplayGainService._();

  static const MethodChannel _channel =
      MethodChannel('musicplayer/media_store');

  // In-memory cache (cleared on hot-restart).
  static final Map<int, LoudnessData> _cache = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the best available [LoudnessData] for [song].
  ///
  /// Checks memory cache → SharedPrefs cache → native tag read.
  /// Always returns a value (may be [LoudnessData.none]).
  static Future<LoudnessData> resolve(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return const LoudnessData.none();

    // 1. Memory cache
    final cached = _cache[song.id];
    if (cached != null) return cached;

    // 2. SharedPrefs cache
    final fromPrefs = await _loadFromPrefs(song.id);
    if (fromPrefs != null) {
      _cache[song.id] = fromPrefs;
      return fromPrefs;
    }

    // 3. Native tag read
    final data = await _readTagsNative(song.path, song.id);
    _cache[song.id] = data;
    await _saveToPrefs(song.id, data);
    return data;
  }

  /// Resolves track and album loudness for [song] in one call.
  ///
  /// Returns a tuple of (trackData, albumData).  Either may be
  /// [LoudnessData.none] when not available.
  static Future<(LoudnessData track, LoudnessData album)> resolveBoth(
    LocalSong song,
  ) async {
    if (kIsWeb || song.path.isEmpty) {
      return (const LoudnessData.none(), const LoudnessData.none());
    }

    final raw = await _readRawTags(song);
    final track = _parseTrack(raw);
    final album = _parseAlbum(raw);
    return (track, album);
  }

  /// Clears the in-memory cache (e.g., after library re-scan).
  static void clearCache() => _cache.clear();

  /// Removes the cached entry for a single song.
  static Future<void> invalidate(int songId) async {
    _cache.remove(songId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rg_$songId');
  }

  // ── Internal — native read ─────────────────────────────────────────────────

  static Future<Map<String, String?>> _readRawTags(LocalSong song) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getReplayGainTags',
        {'path': song.path},
      );
      if (result == null) return {};
      return result.map((k, v) => MapEntry(k, v?.toString()));
    } catch (e) {
      LogService.verbose('ReplayGain', 'Tag read failed for "${song.title}": $e');
      return {};
    }
  }

  static Future<LoudnessData> _readTagsNative(String path, int songId) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getReplayGainTags',
        {'path': path},
      );
      if (result == null) return const LoudnessData.none();
      final tags = result.map((k, v) => MapEntry(k, v?.toString()));
      return _parseTrack(tags);
    } catch (e) {
      LogService.verbose('ReplayGain', 'Native read failed for $songId: $e');
      return const LoudnessData.none();
    }
  }

  // ── Internal — tag parsing ─────────────────────────────────────────────────

  static LoudnessData _parseTrack(Map<String, String?> tags) {
    // Priority 1: REPLAYGAIN_TRACK_GAIN
    final rgGain = _parseGainDb(tags['replayGainTrackGain']);
    if (rgGain != null) {
      return LoudnessData(
        gainDb:     rgGain,
        peakLinear: _parsePeak(tags['replayGainTrackPeak']),
        source:     LoudnessSource.replayGainTrack,
      );
    }

    // Priority 2: R128_TRACK_GAIN (stored as Q7.8 fixed-point integer in dB * 256)
    final r128 = tags['r128TrackGain'];
    if (r128 != null) {
      final parsed = _parseR128(r128);
      if (parsed != null) {
        return LoudnessData(
          gainDb: parsed,
          source: LoudnessSource.r128Track,
        );
      }
    }

    // Priority 3: iTunNORM (Apple iTunes normalization atom)
    final iTunNorm = tags['iTunNORM'];
    if (iTunNorm != null) {
      final parsed = _parseITunNorm(iTunNorm);
      if (parsed != null) return parsed;
    }

    return const LoudnessData.none();
  }

  static LoudnessData _parseAlbum(Map<String, String?> tags) {
    // Priority 1: REPLAYGAIN_ALBUM_GAIN
    final rgGain = _parseGainDb(tags['replayGainAlbumGain']);
    if (rgGain != null) {
      return LoudnessData(
        gainDb:     rgGain,
        peakLinear: _parsePeak(tags['replayGainAlbumPeak']),
        source:     LoudnessSource.replayGainAlbum,
      );
    }

    // Priority 2: R128_ALBUM_GAIN
    final r128 = tags['r128AlbumGain'];
    if (r128 != null) {
      final parsed = _parseR128(r128);
      if (parsed != null) {
        return LoudnessData(
          gainDb: parsed,
          source: LoudnessSource.r128Album,
        );
      }
    }

    // Fallback to track data for album mode
    return _parseTrack(tags);
  }

  // ── Value parsers ──────────────────────────────────────────────────────────

  /// Parses "  -3.45 dB" → -3.45.  Returns null if not parseable.
  static double? _parseGainDb(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'[^0-9.\-+]'), '');
    return double.tryParse(cleaned);
  }

  /// Parses peak value "0.987654" → 0.987654.
  static double? _parsePeak(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return double.tryParse(raw.trim());
  }

  /// R128 gain is stored as integer in units of 1/256 dB (LU relative to -23 LUFS).
  /// Apply +5 dB offset to align with ReplayGain reference level.
  static double? _parseR128(String raw) {
    final v = int.tryParse(raw.trim());
    if (v == null) return null;
    final gainLu = v / 256.0;
    // R128 reference = −23 LUFS; ReplayGain reference = −18 LUFS; offset = +5
    return gainLu + 5.0;
  }

  /// Parses iTunNORM hex string.
  /// Format: " 000002C6 000002C8 00001F4C ..."
  /// Volume difference = 1000/max(track_left, track_right) in linear scale.
  static LoudnessData? _parseITunNorm(String raw) {
    try {
      final parts = raw.trim().split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty).toList();
      if (parts.length < 2) return null;
      final left  = int.parse(parts[0], radix: 16);
      final right = int.parse(parts[1], radix: 16);
      final volume = [left, right].reduce((a, b) => a > b ? a : b);
      if (volume <= 0) return null;
      // Convert: gain = 20 * log10(1000 / volume)
      final gainDb = 20.0 * _log10(1000.0 / volume);
      return LoudnessData(gainDb: gainDb, source: LoudnessSource.iTunNorm);
    } catch (_) {
      return null;
    }
  }

  static double _log10(double x) {
  if (x <= 0) return double.negativeInfinity;
  return math.log(x) / math.ln10;
} 

  // ── SharedPrefs persistence ────────────────────────────────────────────────

  static Future<LoudnessData?> _loadFromPrefs(int songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gainStr = prefs.getString('rg_${songId}_gain');
      final srcIdx  = prefs.getInt('rg_${songId}_src');
      if (gainStr == null || srcIdx == null) return null;
      final gain = double.tryParse(gainStr);
      if (gain == null) return null;
      final peak = double.tryParse(prefs.getString('rg_${songId}_peak') ?? '');
      final src = LoudnessSource.values[srcIdx.clamp(0, LoudnessSource.values.length - 1)];
      return LoudnessData(gainDb: gain, peakLinear: peak, source: src);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToPrefs(int songId, LoudnessData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rg_${songId}_gain', data.gainDb.toString());
      await prefs.setInt('rg_${songId}_src', data.source.index);
      if (data.peakLinear != null) {
        await prefs.setString('rg_${songId}_peak', data.peakLinear.toString());
      }
    } catch (_) {}
  }
}
