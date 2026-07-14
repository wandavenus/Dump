part of '../song_metadata_service.dart';

class SongMetadataService {
  SongMetadataService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const String unknown = 'Unknown';

  // ── In-memory LRU cache (mtime-keyed) ─────────────────────────────────────
  // Keyed by songId; invalidated if the file's mtime changes.
  // Capped at [_maxCacheEntries] with LRU eviction.
  static const int _maxCacheEntries = 100;
  static final LinkedHashMap<int, ({SongInfo info, int mtimeMs})> _cache =
      LinkedHashMap();

  // Deduplicates concurrent requests for the same song.
  static final Map<int, Future<SongInfo>> _inFlight = {};

  // ── Cache helpers ─────────────────────────────────────────────────────────

  static int? _mtimeMs(String path) {
    try {
      return File(path).lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  static void _cachePut(int songId, int? mtimeMs, SongInfo info) {
    if (mtimeMs == null) return;
    _cache.remove(songId);
    _cache[songId] = (info: info, mtimeMs: mtimeMs);
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void invalidate(int songId) => _cache.remove(songId);

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<SongInfo> getSongInfo(LocalSong song) async {
    final mtimeMs = kIsWeb ? null : _mtimeMs(song.path);

    // Cache hit — same file, same mtime
    if (mtimeMs != null) {
      final cached = _cache[song.id];
      if (cached != null && cached.mtimeMs == mtimeMs) {
        // Refresh LRU order
        _cache.remove(song.id);
        _cache[song.id] = cached;
        return cached.info;
      }
    }

    // Deduplicate concurrent opens
    final existing = _inFlight[song.id];
    if (existing != null) return existing;

    final future = _fetchSongInfo(song, mtimeMs);
    _inFlight[song.id] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(song.id);
    }
  }

  static Future<SongInfo> _fetchSongInfo(LocalSong song, int? mtimeMs) async {
    if (kIsWeb) return _buildWebFallback(song);

    // Parallel-fetch from all data sources
    final List<dynamic> results = await Future.wait([
      _loadNativeMetadata(song),   // year, bitrate, sampleRate, composer (MediaMetadataRetriever)
      _loadExtendedTags(song),     // RG/R128 + encoder/isrc/copyright/publisher/comment/lyrics
      _getPlayCount(song.id),      // play count from SharedPreferences history
      ReplayGainService.resolve(song), // applied gain from in-memory/prefs cache
    ]);

    final nativeMeta = results[0] as Map<String, String?>;
    final extTags    = results[1] as Map<String, dynamic>;
    final playCount  = results[2] as int;
    final loudness   = results[3] as LoudnessData;

    // File info — read from dart:io (cheap, sync)
    final path       = song.path;
    final fileName   = path.contains('/') ? path.split('/').last : path;
    final folder     = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    final rawSizeBytes = _fileSizeBytes(path);
    final mtimeMs2   = mtimeMs ?? _mtimeMs(path);
    final modified   = mtimeMs2 != null
        ? _formatDate(DateTime.fromMillisecondsSinceEpoch(mtimeMs2))
        : null;
    final dateAdded = song.dateAdded != null
        ? _formatDate(DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000))
        : null;

    // Lyrics
    final hasLyrics  = extTags['hasLyrics'] == true;
    final lyricsType = hasLyrics
        ? _lyricsTypeLabel(extTags['lyricsType'] as String?)
        : null;

    // albumArtist: skip if same as artist or empty
    final rawAlbumArtist = _clean(song.albumArtist);
    final albumArtist = (rawAlbumArtist == unknown ||
            rawAlbumArtist == _clean(song.artist))
        ? ''
        : rawAlbumArtist;

    final rawGenre = _clean(song.genre);
    final genre    = rawGenre == unknown ? '' : rawGenre;

    // Composer comes from extTags (ExoMetadataReader) and falls back to
    // nativeMeta (MediaMetadataRetriever) for formats not handled by TagBuilder.
    final composer = _nullableStr(extTags['composer'] as String?)
        ?? _nullableStr(nativeMeta['composer']);

    final info = SongInfo(
      // General
      title:       _clean(song.title),
      artist:      _clean(song.artist),
      album:       _clean(song.album),
      albumArtist: albumArtist,
      genre:       genre,
      year:        song.year != null
          ? song.year.toString()
          : (_clean(nativeMeta['year']) == unknown ? '' : _clean(nativeMeta['year'])),
      trackNumber: song.trackNumber?.toString() ?? '',
      discNumber:  song.discNumber?.toString() ?? '',
      duration:    _formatDuration(song.duration),
      composer:    composer,
      comment:     _nullableStr(extTags['comment']    as String?),
      isrc:        _nullableStr(extTags['isrc']       as String?),
      copyright:   _nullableStr(extTags['copyright']  as String?),
      publisher:   _nullableStr(extTags['publisher']  as String?),

      // Audio
      format:      extractAudioFormat(path),
      bitrate:     _formatBitrate(
          song.bitrate?.toString() ?? nativeMeta['bitrate']),
      sampleRate:  _formatSampleRate(
          song.sampleRate?.toString() ?? nativeMeta['sampleRate']),
      encoder:     _nullableStr(extTags['encoder'] as String?),

      // ReplayGain
      rgTrackGain:    _nullableStr(extTags['replayGainTrackGain'] as String?),
      rgTrackPeak:    _nullableStr(extTags['replayGainTrackPeak'] as String?),
      rgAlbumGain:    _nullableStr(extTags['replayGainAlbumGain'] as String?),
      rgAlbumPeak:    _nullableStr(extTags['replayGainAlbumPeak'] as String?),
      r128Track:      _nullableStr(extTags['r128TrackGain'] as String?),
      r128Album:      _nullableStr(extTags['r128AlbumGain'] as String?),
      appliedGainDb:  loudness.hasData ? loudness.gainDb : null,
      loudnessSource: loudness.hasData ? loudness.source.label : null,

      // File
      fileSize:  formatFileSize(rawSizeBytes) ?? unknown,
      filePath:  path,
      fileName:  fileName,
      folder:    folder,
      modified:  modified,
      dateAdded: dateAdded,

      // Embedded Content
      hasEmbeddedLyrics: hasLyrics,
      lyricsType:        lyricsType,

      // Statistics
      playCount: playCount,
    );

    _cachePut(song.id, mtimeMs2, info);
    return info;
  }

  static SongInfo _buildWebFallback(LocalSong song) {
    final path = song.path;
    return SongInfo(
      title:      _clean(song.title),
      artist:     _clean(song.artist),
      album:      _clean(song.album),
      duration:   _formatDuration(song.duration),
      format:     extractAudioFormat(path),
      bitrate:    unknown,
      sampleRate: unknown,
      fileSize:   unknown,
      filePath:   path,
      fileName:   path.contains('/') ? path.split('/').last : path,
      folder:     '',
    );
  }

  // ── Data fetchers ─────────────────────────────────────────────────────────

  static Future<Map<String, String?>> _loadNativeMetadata(LocalSong song) async {
    try {
      final result = await _channel.invokeMapMethod<String, String?>(
        'getAudioMetadata',
        {'path': song.path, 'songId': song.id},
      );
      return result ?? {};
    } catch (e) {
      LogService.log('[SongMetadata] getAudioMetadata failed: $e', level: 'warning');
      return {};
    }
  }

  static Future<Map<String, dynamic>> _loadExtendedTags(LocalSong song) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getSongExtendedTags',
        {'path': song.path},
      );
      return result ?? {};
    } catch (e) {
      LogService.log('[SongMetadata] getSongExtendedTags failed: $e', level: 'warning');
      return {};
    }
  }

  static Future<int> _getPlayCount(int songId) async {
    try {
      final counts = await HistoryService.getPlayCounts();
      return (counts[songId.toString()] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Public helpers ────────────────────────────────────────────────────────

  static String extractAudioFormat(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return unknown;
    return parts.last.toUpperCase();
  }

  /// Formats [bytes] into a human-readable string (B / KB / MB / GB).
  /// Returns null if [bytes] is null or ≤ 0.
  static String? formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final formatted = unitIndex == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(size >= 10 ? 1 : 2);
    return '$formatted ${units[unitIndex]}';
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static int? _fileSizeBytes(String path) {
    try {
      final len = File(path).lengthSync();
      return len > 0 ? len : null;
    } catch (_) {
      return null;
    }
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}  $h:$min';
  }

  static String? _nullableStr(String? v) {
    final s = v?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String _clean(String? value) {
    final sanitized = value?.trim();
    if (sanitized == null || sanitized.isEmpty || sanitized == '<unknown>') {
      return unknown;
    }
    return sanitized;
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
    final khz = sampleRate / 1000;
    final formatted = khz == khz.roundToDouble()
        ? khz.toStringAsFixed(0)
        : khz.toStringAsFixed(1);
    return '$formatted kHz';
  }

  static String? _lyricsTypeLabel(String? type) => switch (type) {
        'LRC'   => 'LRC (synced)',
        'PLAIN' => 'Plain text',
        _       => null,
      };
}
