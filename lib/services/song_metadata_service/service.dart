part of '../song_metadata_service.dart';

class SongMetadataService {
  SongMetadataService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const String unknown = 'Unknown';

  // ── In-memory result cache (mtime-keyed) ──────────────────────────────────
  //
  // Only matters on API 29-30 devices (e.g. this project's Android 11 test
  // device), where bitrate/sampleRate aren't in the MediaStore projection and
  // every Song Info open pays for a MediaMetadataRetriever round-trip. On
  // API 31+ the fast path above already avoids native I/O entirely, so the
  // cache is a pure no-op cost there (one map lookup).
  //
  // Keyed by songId; invalidated automatically if the file's mtime changes
  // (e.g. re-tagged externally), so a stale entry can never be served.
  // Capped at [_maxCacheEntries] with LRU eviction to keep memory bounded —
  // important on a 6 GB RAM device.
  static const int _maxCacheEntries = 100;
  static final LinkedHashMap<int, ({SongInfo info, int mtimeMs})> _cache =
      LinkedHashMap();

  // Deduplicates concurrent slow-path requests for the same song: if the
  // Song Info sheet somehow triggers two lookups for the same songId before
  // the first native call returns, the second one just awaits the first's
  // result instead of issuing its own MediaMetadataRetriever round-trip.
  static final Map<int, Future<SongInfo>> _inFlight = {};

  static int? _mtimeMs(String path) {
    try {
      return File(path).lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  static void _cachePut(int songId, int? mtimeMs, SongInfo info) {
    if (mtimeMs == null) return; // can't validate freshness later — skip.
    _cache.remove(songId);
    _cache[songId] = (info: info, mtimeMs: mtimeMs);
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Removes the cached entry for a single song (e.g. after deletion from
  /// the library, so a stale [SongInfo] can never be served for a reused
  /// songId).
  static void invalidate(int songId) {
    _cache.remove(songId);
  }

  /// Returns full technical metadata for [song].
  ///
  /// Fast path (API 31+ devices): bitrate and sampleRate are already present
  /// in [LocalSong] from the expanded MediaStore projection — no native I/O.
  /// Slow path (API 29-30): falls back to [MediaMetadataRetriever] via the
  /// native [getAudioMetadata] channel call, with an in-memory cache (see
  /// above) so re-opening Song Info for the same unchanged file is instant.
  /// File size is read directly from [dart:io] on all API levels.
  static Future<SongInfo> getSongInfo(LocalSong song) async {
    final fileSizeStr = _readFileSizeString(song.path);

    // Fast path — MediaStore already gave us bitrate/sampleRate (API 31+).
    if (!kIsWeb && (song.bitrate != null || song.sampleRate != null)) {
      return SongInfo(
        title:      _clean(song.title),
        artist:     _clean(song.albumArtist ?? song.artist),
        album:      _clean(song.album),
        year:       song.year != null ? song.year.toString() : unknown,
        duration:   _formatDuration(song.duration),
        format:     extractAudioFormat(song.path),
        bitrate:    _formatBitrate(song.bitrate?.toString()),
        sampleRate: _formatSampleRate(song.sampleRate?.toString()),
        fileSize:   formatFileSize(int.tryParse(fileSizeStr)),
        filePath:   _clean(song.path),
      );
    }

    // Slow-path cache lookup — skip the native round-trip if we already
    // fetched this exact (unchanged) file's metadata before.
    final mtimeMs = kIsWeb ? null : _mtimeMs(song.path);
    if (mtimeMs != null) {
      final cached = _cache[song.id];
      if (cached != null && cached.mtimeMs == mtimeMs) {
        _cache.remove(song.id);
        _cache[song.id] = cached; // move to MRU position
        return cached.info;
      }
    }

    // Slow path — call MediaMetadataRetriever via native channel.
    // Deduplicate: if a lookup for this songId is already in flight, await
    // that instead of starting a second native round-trip.
    final existing = _inFlight[song.id];
    if (existing != null) return existing;

    final future = _fetchSlowPath(song, fileSizeStr, mtimeMs);
    _inFlight[song.id] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(song.id); // ignore: unawaited_futures
    }
  }

  static Future<SongInfo> _fetchSlowPath(
    LocalSong song,
    String fileSizeStr,
    int? mtimeMs,
  ) async {
    final metadata = await _loadNativeMetadata(song);
    final info = SongInfo(
      title:      _clean(song.title),
      artist:     _clean(song.albumArtist ?? song.artist),
      album:      _clean(song.album),
      year:       _clean(metadata['year'] ?? song.year?.toString()),
      duration:   _formatDuration(song.duration),
      format:     extractAudioFormat(song.path),
      bitrate:    _formatBitrate(metadata['bitrate']),
      sampleRate: _formatSampleRate(metadata['sampleRate']),
      fileSize:   formatFileSize(
                    int.tryParse(metadata['fileSize'] ?? fileSizeStr)),
      filePath:   _clean(song.path),
    );
    _cachePut(song.id, mtimeMs, info);
    return info;
  }

  static Future<Map<String, String>> _loadNativeMetadata(LocalSong song) async {
    if (kIsWeb || song.path.trim().isEmpty) return const <String, String>{};

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getAudioMetadata',
        {'path': song.path, 'songId': song.id},
      );

      if (result == null) return const <String, String>{};

      return result.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load metadata for ${song.path}: $error\n$stackTrace');
      return const <String, String>{};
    } catch (error, stackTrace) {
      debugPrint('Invalid metadata payload for ${song.path}: $error\n$stackTrace');
      return const <String, String>{};
    }
  }

  // ── File size (Dart-side, no native round-trip needed) ───────────────────

  /// Returns the file size as a raw byte-count string, or empty string on error.
  static String _readFileSizeString(String path) {
    if (kIsWeb || path.isEmpty) return '';
    try {
      final bytes = File(path).lengthSync();
      return bytes > 0 ? bytes.toString() : '';
    } catch (_) {
      return '';
    }
  }

  // ── Format helpers ────────────────────────────────────────────────────────

  static String extractAudioFormat(String path) {
    final sanitizedPath = path.split('?').first.trim();
    if (sanitizedPath.isEmpty || !sanitizedPath.contains('.')) {
      return unknown;
    }

    final extension = sanitizedPath.split('.').last.toUpperCase();
    return extension.isEmpty ? unknown : extension;
  }

  static String formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return unknown;

    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final formatted = unitIndex == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(size >= 10 ? 1 : 2);
    return '$formatted ${units[unitIndex]}';
  }

  static String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return unknown;

    final hours   = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatBitrate(String? rawBitrate) {
    final bitrate = int.tryParse(rawBitrate ?? '');
    if (bitrate == null || bitrate <= 0) return unknown;

    return '${(bitrate / 1000).round()} kbps';
  }

  static String _formatSampleRate(String? rawSampleRate) {
    final sampleRate = int.tryParse(rawSampleRate ?? '');
    if (sampleRate == null || sampleRate <= 0) return unknown;

    final khz       = sampleRate / 1000;
    final formatted = khz == khz.roundToDouble()
        ? khz.toStringAsFixed(0)
        : khz.toStringAsFixed(1);
    return '$formatted kHz';
  }

  static String _clean(String? value) {
    final sanitized = value?.trim();
    if (sanitized == null || sanitized.isEmpty || sanitized == '<unknown>') {
      return unknown;
    }

    return sanitized;
  }
}
