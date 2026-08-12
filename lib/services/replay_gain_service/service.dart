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

  static const MethodChannel _channel = MethodChannel(
    'musicplayer/media_store',
  );

  // In-memory cache (cleared on hot-restart).
  static final Map<int, LoudnessData> _cache = {};
  static final Map<int, _ReplayGainFileIdentity> _cacheIdentity = {};

  // Deduplicates concurrent resolve() calls for the same song — e.g. rapid
  // track skips or the UI + playback path both resolving loudness for the
  // same song before either finishes. The second caller just awaits the
  // first's in-flight future instead of issuing its own SharedPrefs read +
  // native tag round-trip.
  static final Map<int, Future<LoudnessData>> _inFlight = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the best available [LoudnessData] for [song].
  ///
  /// Checks memory cache → SharedPrefs cache → native tag read.
  /// Always returns a value (may be [LoudnessData.none]).
  static Future<LoudnessData> resolve(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return const LoudnessData.none();

    // 1. Memory cache, only when it still belongs to the current file.
    final identity = await _fileIdentity(song.path);
    final cached = _cache[song.id];
    if (cached != null &&
        identity != null &&
        _cacheIdentity[song.id] == identity) {
      return cached;
    }
    if (cached != null) {
      _cache.remove(song.id);
      _cacheIdentity.remove(song.id);
    }

    // 2. In-flight dedup
    final existing = _inFlight[song.id];
    if (existing != null) return existing;

    final future = _resolveUncached(song, identity);
    _inFlight[song.id] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(song.id); // ignore: unawaited_futures
    }
  }

  static Future<LoudnessData> _resolveUncached(
    LocalSong song,
    _ReplayGainFileIdentity? identity,
  ) async {
    // SharedPrefs cache
    final fromPrefs = await _loadFromPrefs(song, identity);
    if (fromPrefs != null) {
      _cache[song.id] = fromPrefs;
      _cacheIdentity[song.id] = identity!;
      return fromPrefs;
    }

    // Native tag read
    final data = await _readTagsNative(song.path, song.id);
    _cache[song.id] = data;
    if (identity != null) {
      _cacheIdentity[song.id] = identity;
      await _saveToPrefs(song.id, data, identity);
    }
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
  static void clearCache() {
    _cache.clear();
    _cacheIdentity.clear();
  }

  /// Removes the cached entry for a single song.
  static Future<void> invalidate(int songId) async {
    _cache.remove(songId);
    _cacheIdentity.remove(songId);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('rg_${songId}_gain'),
      prefs.remove('rg_${songId}_peak'),
      prefs.remove('rg_${songId}_src'),
      prefs.remove('rg_${songId}_path'),
      prefs.remove('rg_${songId}_size'),
      prefs.remove('rg_${songId}_mtime'),
    ]);
  }

  static Future<_ReplayGainFileIdentity?> _fileIdentity(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getReplayGainFileIdentity',
        {'path': path},
      );
      final size = (raw?['size'] as num?)?.toInt();
      final mtime = (raw?['mtimeMs'] as num?)?.toInt();
      if (raw == null ||
          size == null ||
          mtime == null ||
          size < 0 ||
          mtime < 0) {
        return null;
      }
      return _ReplayGainFileIdentity(path, size, mtime);
    } on Exception catch (_) {
      return null;
    }
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
    } on Exception catch (e) {
      LogService.verbose(
        'ReplayGain',
        'Tag read failed for "${song.title}": $e',
      );
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
    } on Exception catch (e) {
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
        gainDb: rgGain,
        peakLinear: _parsePeak(tags['replayGainTrackPeak']),
        source: LoudnessSource.replayGainTrack,
      );
    }

    // Priority 2: R128_TRACK_GAIN (stored as Q7.8 fixed-point integer in dB * 256)
    final r128 = tags['r128TrackGain'];
    if (r128 != null) {
      final parsed = _parseR128(r128);
      if (parsed != null) {
        return LoudnessData(gainDb: parsed, source: LoudnessSource.r128Track);
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
        gainDb: rgGain,
        peakLinear: _parsePeak(tags['replayGainAlbumPeak']),
        source: LoudnessSource.replayGainAlbum,
      );
    }

    // Priority 2: R128_ALBUM_GAIN
    final r128 = tags['r128AlbumGain'];
    if (r128 != null) {
      final parsed = _parseR128(r128);
      if (parsed != null) {
        return LoudnessData(gainDb: parsed, source: LoudnessSource.r128Album);
      }
    }

    // Fallback to track data for album mode
    return _parseTrack(tags);
  }

  // ── Value parsers ──────────────────────────────────────────────────────────

  /// Parses "  -3.45 dB" → -3.45.  Returns null if not parseable.
  static double? _parseGainDb(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    // Require the complete value so a locale-formatted or malformed value
    // such as "+1,23 dB" is rejected instead of being truncated to +1.
    final match = RegExp(
      r'^\s*([+-]?\d+(?:\.\d+)?)\s*(?:dB)?\s*$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    return value?.isFinite == true ? value : null;
  }

  /// Parses peak value "0.987654" → 0.987654.
  static double? _parsePeak(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    return value?.isFinite == true && value! >= 0.0 ? value : null;
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
      final parts = raw
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length < 2) return null;
      final left = int.parse(parts[0], radix: 16);
      final right = int.parse(parts[1], radix: 16);
      final volume = [left, right].reduce((a, b) => a > b ? a : b);
      if (volume <= 0) return null;
      // Convert: gain = 20 * log10(1000 / volume)
      final gainDb = 20.0 * _log10(1000.0 / volume);
      return LoudnessData(gainDb: gainDb, source: LoudnessSource.iTunNorm);
    } on Exception catch (_) {
      return null;
    }
  }

  static double _log10(double x) {
    if (x <= 0) return double.negativeInfinity;
    return math.log(x) / math.ln10;
  }

  // ── SharedPrefs persistence ────────────────────────────────────────────────

  static Future<LoudnessData?> _loadFromPrefs(
    LocalSong song,
    _ReplayGainFileIdentity? identity,
  ) async {
    try {
      if (identity == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final songId = song.id;
      if (prefs.getString('rg_${songId}_path') != song.path ||
          prefs.getInt('rg_${songId}_size') != identity.size ||
          prefs.getInt('rg_${songId}_mtime') != identity.mtimeMs) {
        return null;
      }
      final gainStr = prefs.getString('rg_${songId}_gain');
      final srcIdx = prefs.getInt('rg_${songId}_src');
      if (gainStr == null || srcIdx == null) return null;
      final gain = double.tryParse(gainStr);
      if (gain == null || !gain.isFinite) return null;
      final peak = double.tryParse(prefs.getString('rg_${songId}_peak') ?? '');
      if (peak != null && (!peak.isFinite || peak < 0.0)) return null;
      final src = LoudnessSource
          .values[srcIdx.clamp(0, LoudnessSource.values.length - 1)];
      return LoudnessData(gainDb: gain, peakLinear: peak, source: src);
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> _saveToPrefs(
    int songId,
    LoudnessData data, [
    _ReplayGainFileIdentity? identity,
  ]) async {
    try {
      if (identity == null) return;
      final prefs = await SharedPreferences.getInstance();
      final writes = <Future<bool>>[
        prefs.setString('rg_${songId}_path', identity.path),
        prefs.setInt('rg_${songId}_size', identity.size),
        prefs.setInt('rg_${songId}_mtime', identity.mtimeMs),
        prefs.setString('rg_${songId}_gain', data.gainDb.toString()),
        prefs.setInt('rg_${songId}_src', data.source.index),
      ];
      if (data.peakLinear != null && data.peakLinear!.isFinite) {
        writes.add(
          prefs.setString('rg_${songId}_peak', data.peakLinear.toString()),
        );
      } else {
        writes.add(prefs.remove('rg_${songId}_peak'));
      }
      // Tulis ke 3 key secara paralel (bukan berurutan) untuk mengurangi
      // waktu tunggu I/O per lagu saat scanning library besar.
      await Future.wait(writes);
    } on Exception catch (_) {}
  }

  // ── Batch library scan ────────────────────────────────────────────────────

  static bool _cancelRequested = false;

  /// Live progress state for a [scanLibrary] run.
  /// Bind UI widgets to this notifier — it updates after every song.
  static final ValueNotifier<BatchScanProgress> scanProgress = ValueNotifier(
    const BatchScanProgress(),
  );

  /// Requests cancellation of the active [scanLibrary] run.
  /// The current song finishes before the loop stops.
  static void cancelScan() => _cancelRequested = true;

  /// Scan a single [song] via the native EBU R128 (libebur128) scanner.
  ///
  /// On success the result is stored in MetadataCacheDb (by the native
  /// handler) and in the Dart memory cache + SharedPreferences. If
  /// [writeTags] is true, the measured gain/peak is also written
  /// permanently into the file's own tags via TagLib (see
  /// [ReplayGainService.writeReplayGain]) — off by default since most users
  /// only want in-app normalization, not a permanent file modification.
  /// Returns `null` if the file cannot be decoded.
  static Future<LoudnessData?> scanOneSong(
    LocalSong song, {
    bool writeTags = false,
  }) async {
    final scan = await _scanTrackResult(song);
    if (scan == null) return null;

    final integratedLufs = scan.integratedLufs;
    if (writeTags && integratedLufs != null) {
      final wrote = await writeReplayGain(
        song: song,
        trackGainDb: scan.data.gainDb,
        trackPeak: scan.data.peakLinear ?? 0.0,
        trackIntegratedLufs: integratedLufs,
        expectedFileSize: scan.identity.size,
        expectedFileMtimeMs: scan.identity.mtimeMs,
      );
      if (!wrote) return null;
      final afterWrite = await _fileIdentity(song.path);
      if (afterWrite == null) return null;
      _cacheIdentity[song.id] = afterWrite;
      _cache[song.id] = scan.data;
      await _saveToPrefs(song.id, scan.data, afterWrite);
    } else {
      _cacheIdentity[song.id] = scan.identity;
      _cache[song.id] = scan.data;
      await _saveToPrefs(song.id, scan.data, scan.identity);
    }
    return scan.data;
  }

  /// Runs one native single-track scan with the identity guarded the same way
  /// [scanOneSong] used to: identity before → scanTrack → identity after — a
  /// change mid-scan (file replaced/edited) discards the measurement.
  ///
  /// Returns null when the file cannot be decoded or changed during the scan.
  /// [integratedLufs] is kept out of [LoudnessData] (which deliberately stores
  /// only gain/peak) because the batched tag-write path needs the raw LUFS
  /// value to persist R128 fields.
  static Future<_TrackScan?> _scanTrackResult(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return null;
    try {
      final before = await _fileIdentity(song.path);
      if (before == null) return null;
      final raw = await _channel.invokeMapMethod<String, dynamic>('scanTrack', {
        'path': song.path,
      });
      if (raw == null) return null;
      final gainDb = (raw['trackGainDb'] as num?)?.toDouble();
      final peak = (raw['trackPeak'] as num?)?.toDouble();
      final integratedLufs = (raw['integratedLufs'] as num?)?.toDouble();
      if (gainDb == null || !gainDb.isFinite) return null;
      final cleanPeak = peak != null && peak.isFinite && peak >= 0.0
          ? peak
          : null;
      if (integratedLufs != null && !integratedLufs.isFinite) return null;
      final afterScan = await _fileIdentity(song.path);
      if (afterScan != before) {
        LogService.warn(
          'ReplayGain',
          '_scanTrackResult "${song.title}" discarded: file changed during scan',
        );
        return null;
      }
      return _TrackScan(
        data: LoudnessData(
          gainDb: gainDb,
          peakLinear: cleanPeak,
          source: LoudnessSource.replayGainTrack,
        ),
        integratedLufs: integratedLufs,
        identity: before,
      );
    } on PlatformException catch (e) {
      LogService.warn(
        'ReplayGain',
        '_scanTrackResult "${song.title}": ${e.code} – ${e.message}',
      );
      return null;
    } on Object catch (e) {
      LogService.warn('ReplayGain', '_scanTrackResult "${song.title}": $e');
      return null;
    }
  }

  /// Batch-scan [songs] with the native EBU R128 scanner using controlled
  /// concurrency.
  ///
  /// Two songs are decoded in parallel on the native side (the native
  /// `rg-scan` executor has 2 threads).  Each pair is awaited before moving
  /// on so progress stays predictable and cancellation is responsive.
  ///
  /// Songs already in the in-memory cache with a non-zero gain are skipped.
  /// Progress is reported via [scanProgress].  Call [cancelScan] to abort
  /// mid-run; the current pair of songs always finishes before stopping.
  ///
  /// Returns immediately (no-op) if a scan is already running.
  ///
  /// If [writeTags] is true, every successfully-scanned song also gets its
  /// measurement written permanently into the file's own tags (see
  /// [scanOneSong]). Off by default.
  static Future<void> scanLibrary(
    List<LocalSong> songs, {
    bool writeTags = false,
  }) async {
    if (kIsWeb || songs.isEmpty) return;
    if (scanProgress.value.running) return;

    final toScan = <LocalSong>[];
    final seenIds = <int>{};
    for (final song in songs) {
      // Defensive dedup (1.5.23): a duplicated songId in the input must never
      // be scanned twice nor queued twice for tag writing — a duplicated write
      // request could even land in two different parallel batches and race on
      // the same file. MediaStore rows are unique by _ID today, but nothing
      // downstream should depend on the caller never passing duplicates.
      if (!seenIds.add(song.id)) continue;
      final c = _cache[song.id];
      final identity = await _fileIdentity(song.path);
      if (c == null ||
          c.gainDb == 0.0 ||
          identity == null ||
          _cacheIdentity[song.id] != identity) {
        toScan.add(song);
      }
    }

    if (toScan.isEmpty) {
      scanProgress.value = const BatchScanProgress(
        currentTitle: 'Semua lagu sudah punya data Audio Normalize',
      );
      return;
    }

    _cancelRequested = false;
    scanProgress.value = BatchScanProgress(total: toScan.length, running: true);

    // Pre-authorize write access for every song up front so the whole batch
    // only ever shows ONE system confirmation dialog (Android 11+), instead
    // of one dialog per file as songs are scanned/written. The per-song
    // writeReplayGain calls below will see access already granted and won't
    // trigger any further dialogs. Songs the user declines here are simply
    // skipped when writing (their scan result is still kept/cached).
    Map<int, bool> writeAccessById = const {};
    if (writeTags) {
      writeAccessById = await requestBatchWriteAccess(
        toScan.map((s) => s.id).toList(),
      );
    }

    // 2 concurrent scans — matches the native executor thread count.
    // Snapdragon 730 hardware MediaCodec handles 2 parallel audio decoders
    // without significant CPU or thermal contention.
    const concurrency = 2;
    var failed = 0;

    // R-B (1.5.21): measurements destined for permanent tags are collected
    // here and written in ONE native batch call when the scan finishes (see
    // _flushPendingWrites) — no per-song MethodChannel round trip.
    final pendingWrites = <ReplayGainWriteRequest>[];

    for (var base = 0; base < toScan.length; base += concurrency) {
      if (_cancelRequested) {
        // Still persist whatever was already measured — the old per-song flow
        // wrote tags as songs completed, so cancellation must not silently
        // drop results the user asked to write.
        failed += await _flushPendingWrites(pendingWrites);
        scanProgress.value = scanProgress.value.copyWith(
          done: base,
          running: false,
          cancelled: true,
        );
        LogService.log(
          'ReplayGain',
          'Scan dibatalkan pada $base/${toScan.length}',
        );
        return;
      }

      final end = (base + concurrency).clamp(0, toScan.length);
      final chunk = toScan.sublist(base, end);

      // Show the first song of the chunk as the "current" title
      scanProgress.value = scanProgress.value.copyWith(
        done: base,
        currentTitle: chunk.first.title,
      );

      // Fire both scans concurrently; scanOneSong never throws (catches all).
      // Only pass writeTags through for songs whose write access was
      // actually granted in the pre-authorization above — declined songs
      // still get scanned (for in-app normalization) but skip the file
      // write, and critically do NOT trigger a fallback per-file dialog.
      // Fire both scans concurrently; _scanTrackResult never throws (catches
      // all). Measurements are cached immediately; songs whose write access
      // was granted in the pre-authorization are collected for the batched
      // tag write — declined songs still get scanned (for in-app
      // normalization) but skip the file write, and critically do NOT
      // trigger a fallback per-file dialog.
      final scans = await Future.wait(chunk.map((s) => _scanTrackResult(s)));

      for (var i = 0; i < scans.length; i++) {
        final scan = scans[i];
        final song = chunk[i];
        if (scan == null) {
          failed++;
          continue;
        }
        // Same cache bookkeeping as scanOneSong's writeTags:false path.
        _cacheIdentity[song.id] = scan.identity;
        _cache[song.id] = scan.data;
        await _saveToPrefs(song.id, scan.data, scan.identity);

        final integratedLufs = scan.integratedLufs;
        if (writeTags &&
            (writeAccessById[song.id] ?? false) &&
            integratedLufs != null) {
          pendingWrites.add(
            ReplayGainWriteRequest(
              song: song,
              trackGainDb: scan.data.gainDb,
              trackPeak: scan.data.peakLinear ?? 0.0,
              trackIntegratedLufs: integratedLufs,
              expectedFileSize: scan.identity.size,
              expectedFileMtimeMs: scan.identity.mtimeMs,
            ),
          );
        }
      }

      scanProgress.value = scanProgress.value.copyWith(done: end);

      // Minimal yield between chunks to keep the event loop responsive and
      // allow cancellation checks without adding noticeable total latency.
      if (end < toScan.length) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    // R-B (1.5.21): persist every scanned measurement in ONE native batch
    // call instead of one writeReplayGain round trip per song — the single
    // biggest channel-overhead win for library-wide "scan + write" runs.
    failed += await _flushPendingWrites(pendingWrites);

    scanProgress.value = BatchScanProgress(
      done: toScan.length,
      total: toScan.length,
      failed: failed,
      running: false,
    );
    LogService.log(
      'ReplayGain',
      'Batch scan selesai: ${toScan.length - failed} berhasil, $failed gagal',
    );
  }

  // ── Album scan (native EBU R128, libebur128) ───────────────────────────────

  /// Scans every song in [songs] (expected to belong to one album) and
  /// returns per-track loudness plus the shared album gain, computed via
  /// libebur128's EBU Tech 3341 album-loudness algorithm on the native side
  /// (not a naive average of independently-measured track LUFS values).
  ///
  /// Results are also written into the Dart memory cache + SharedPreferences
  /// for each successfully-scanned track (as [LoudnessSource.replayGainAlbum]
  /// so playback picks up the album gain immediately). Does NOT write tags
  /// to the files — call [writeReplayGain] per track afterwards if the user
  /// wants the measurement persisted to disk.
  static Future<AlbumScanResult> scanAlbum(List<LocalSong> songs) async {
    if (kIsWeb || songs.isEmpty) {
      return const AlbumScanResult(
        trackResults: {},
        albumGainDb: 0.0,
        albumPeak: null,
        albumIntegratedLufs: null,
        failedPaths: [],
      );
    }
    try {
      // F3 (RG-01): capture identities BEFORE the scan. A file that changes
      // mid-scan must never get its (stale) measurement cached under the new
      // identity — mirror the before/after guard _scanTrackResult already uses.
      final beforeById = <int, _ReplayGainFileIdentity?>{};
      for (final s in songs) {
        beforeById[s.id] = await _fileIdentity(s.path);
      }

      final raw = await _channel.invokeMapMethod<String, dynamic>('scanAlbum', {
        'paths': songs.map((s) => s.path).toList(),
      });
      if (raw == null) {
        return AlbumScanResult(
          trackResults: const {},
          albumGainDb: 0.0,
          albumPeak: null,
          albumIntegratedLufs: null,
          failedPaths: songs.map((s) => s.path).toList(),
        );
      }

      final albumGainDb = (raw['albumGainDb'] as num?)?.toDouble() ?? 0.0;
      final albumPeak = (raw['albumPeak'] as num?)?.toDouble();
      final albumLufs = (raw['albumIntegratedLufs'] as num?)?.toDouble();
      final tracksRaw = (raw['tracks'] as Map?)?.cast<String, dynamic>() ?? {};
      final failedPaths = (raw['failedPaths'] as List?)?.cast<String>() ?? [];

      final byPath = {for (final s in songs) s.path: s};
      final trackResults = <int, TrackLoudnessResult>{};

      for (final entry in tracksRaw.entries) {
        final song = byPath[entry.key];
        if (song == null) continue;
        final t = (entry.value as Map).cast<String, dynamic>();
        final trackGainDb = (t['trackGainDb'] as num?)?.toDouble() ?? 0.0;
        final trackPeak = (t['trackPeak'] as num?)?.toDouble();
        final integratedLufs = (t['integratedLufs'] as num?)?.toDouble();

        final albumData = LoudnessData(
          gainDb: albumGainDb,
          peakLinear: albumPeak,
          source: LoudnessSource.replayGainAlbum,
        );
        // Only cache when the file survived the scan unchanged (F3).
        final after = await _fileIdentity(song.path);
        final prior = beforeById[song.id];
        if (prior != null && after != null && after == prior) {
          _cache[song.id] = albumData;
          _cacheIdentity[song.id] = after;
          await _saveToPrefs(song.id, albumData, after);
        }

        trackResults[song.id] = TrackLoudnessResult(
          song: song,
          trackGainDb: trackGainDb,
          trackPeak: trackPeak,
          trackIntegratedLufs: integratedLufs,
        );
      }

      return AlbumScanResult(
        trackResults: trackResults,
        albumGainDb: albumGainDb,
        albumPeak: albumPeak,
        albumIntegratedLufs: albumLufs,
        failedPaths: failedPaths,
      );
    } on PlatformException catch (e) {
      LogService.warn('ReplayGain', 'scanAlbum: ${e.code} – ${e.message}');
      return AlbumScanResult(
        trackResults: const {},
        albumGainDb: 0.0,
        albumPeak: null,
        albumIntegratedLufs: null,
        failedPaths: songs.map((s) => s.path).toList(),
      );
    }
  }

  // ── Library-wide tag removal (Settings → Audio Normalize) ──────────────────

  /// Removes REPLAYGAIN_*/R128_* tags from every song in [songs] (the whole
  /// library, as passed from Settings) with at most one batch write-access
  /// grant dialog (Android 11+). Per-song failures (declined permission,
  /// unsupported format, stale scan) never fail the batch; files without any
  /// loudness tags are no-ops and count as removed.
  ///
  /// Returns how many songs were cleaned and how many failed.
  static Future<RemoveRgResult> removeReplayGainFromLibrary(
    List<LocalSong> songs,
  ) async {
    if (kIsWeb || songs.isEmpty) {
      return const RemoveRgResult(removed: 0, failed: 0);
    }

    // Defensive dedup — a duplicated songId must never be removed twice (or
    // race on the same file through two channel calls).
    final unique = <LocalSong>[];
    final seen = <int>{};
    for (final s in songs) {
      if (seen.add(s.id)) unique.add(s);
    }

    // One batch grant for the whole library; declined songs fail per-song.
    final granted = await requestBatchWriteAccess(
      unique.map((s) => s.id).toList(),
    );

    var removed = 0;
    var failed = 0;
    for (final song in unique) {
      if (!(granted[song.id] ?? false)) {
        failed++;
        continue;
      }
      final ok = await removeReplayGainTags(song);
      if (ok) {
        removed++;
      } else {
        failed++;
      }
    }
    return RemoveRgResult(removed: removed, failed: failed);
  }

  // ── Batch write-access pre-authorization ───────────────────────────────────

  /// Pre-authorizes MediaStore write access for every song in [songIds] with
  /// **at most one** system confirmation dialog for the whole batch
  /// (Android 11+, via a single native `MediaStore.createWriteRequest`
  /// grant). Call this once before issuing a series of [writeReplayGain] /
  /// [removeReplayGainTags] calls (e.g. writing an entire album or library)
  /// — those calls will then find access already granted and proceed
  /// without any further dialogs.
  ///
  /// Returns a map of songId to whether that song is now writable. On
  /// Android 10, the OS has no batch-grant API, so the native side falls
  /// back to resolving each file one at a time (still only one dialog on
  /// screen at any moment, just not collapsed into a single dialog for the
  /// whole batch — a platform limitation, not something Dart can change).
  ///
  /// Never requests `WRITE_EXTERNAL_STORAGE` or `MANAGE_EXTERNAL_STORAGE`.
  static Future<Map<int, bool>> requestBatchWriteAccess(
    List<int> songIds,
  ) async {
    if (kIsWeb || songIds.isEmpty) return {};
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'requestReplayGainWriteAccessBatch',
        {'songIds': songIds},
      );
      if (raw == null) return {for (final id in songIds) id: false};
      return raw.map((k, v) => MapEntry(int.parse(k), v == true));
    } on PlatformException catch (e) {
      LogService.warn(
        'ReplayGain',
        'requestBatchWriteAccess (${songIds.length} songs): ${e.code} – ${e.message}',
      );
      return {for (final id in songIds) id: false};
    }
  }

  // ── Permanent tag writing (TagLib, native) ─────────────────────────────────

  /// Writes the measured loudness for [song] permanently into the file's own
  /// tags (REPLAYGAIN_TRACK_GAIN/_PEAK, and for Ogg Opus also
  /// R128_TRACK_GAIN) via the native TagLib-backed writer. Pass
  /// [albumGainDb]/[albumPeak]/[albumIntegratedLufs] together (e.g. from
  /// [scanAlbum]) to also write REPLAYGAIN_ALBUM_GAIN/_PEAK /
  /// R128_ALBUM_GAIN in the same call.
  ///
  /// All other metadata (cover art, lyrics, ISRC, disc/track number,
  /// comments, album artist, etc.) is preserved untouched — only the
  /// loudness-related tag fields are added or replaced. Audio is never
  /// re-encoded.
  ///
  /// Returns `true` on success. On failure, check [LogService] for the
  /// native error code (e.g. unsupported format for M4A/AAC — writing is
  /// only supported for MP3/FLAC/Ogg Vorbis/Ogg Opus; permission failure if
  /// the file isn't writable; `WRITE_ACCESS_DENIED` if the user declined the
  /// system write-access dialog; `VERIFICATION_FAILED` if the write couldn't
  /// be confirmed to have persisted — in that case native already attempted
  /// a byte-exact rollback of the original tag data before returning).
  ///
  /// Requires [song.id] to resolve a fresh MediaStore write grant on the
  /// native side (Android 10+ scoped storage) — see `MediaStoreWriteGate`.
  static Future<bool> writeReplayGain({
    required LocalSong song,
    required double trackGainDb,
    required double trackPeak,
    required double trackIntegratedLufs,
    int? expectedFileSize,
    int? expectedFileMtimeMs,
    double? albumGainDb,
    double? albumPeak,
    double? albumIntegratedLufs,
  }) async {
    if (kIsWeb || song.path.isEmpty) return false;
    if (!trackGainDb.isFinite ||
        !trackPeak.isFinite ||
        trackPeak < 0.0 ||
        !trackIntegratedLufs.isFinite) {
      return false;
    }
    final albumValues = [albumGainDb, albumPeak, albumIntegratedLufs];
    if (albumValues.any((value) => value != null) &&
            albumValues.any((value) => value == null || !value.isFinite) ||
        albumPeak != null && albumPeak < 0.0) {
      return false;
    }
    if (expectedFileSize != null && expectedFileMtimeMs != null) {
      final current = await _fileIdentity(song.path);
      if (current == null ||
          current.size != expectedFileSize ||
          current.mtimeMs != expectedFileMtimeMs) {
        LogService.warn(
          'ReplayGain',
          'writeReplayGain "${song.title}" rejected: stale scan',
        );
        return false;
      }
    }
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('writeReplayGain', {
            'path': song.path,
            'songId': song.id,
            'trackGainDb': trackGainDb,
            'trackPeak': trackPeak,
            'integratedLufs': trackIntegratedLufs,
            'fileSize': ?expectedFileSize,
            'fileMtimeMs': ?expectedFileMtimeMs,
            'albumGainDb': ?albumGainDb,
            'albumPeak': ?albumPeak,
            'albumIntegratedLufs': ?albumIntegratedLufs,
          });
      final success = raw?['success'] == true;
      if (!success) {
        LogService.warn(
          'ReplayGain',
          'writeReplayGain "${song.title}" failed: ${raw?['error']}',
        );
      } else {
        // Tags on disk changed -> invalidate so the next resolve() re-reads
        // from the file instead of serving a pre-write cached value.
        await invalidate(song.id);
      }
      return success;
    } on PlatformException catch (e) {
      LogService.warn(
        'ReplayGain',
        'writeReplayGain "${song.title}": ${e.code} – ${e.message}',
      );
      return false;
    }
  }

  /// Removes REPLAYGAIN_*/R128_* tags from [song]'s file, leaving all other
  /// metadata intact. Returns `true` on success.
  ///
  /// Requires [song.id] — see [writeReplayGain] for why.
  static Future<bool> removeReplayGainTags(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return false;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'removeReplayGain',
        {'path': song.path, 'songId': song.id},
      );
      final success = raw?['success'] == true;
      if (!success) {
        LogService.warn(
          'ReplayGain',
          'removeReplayGainTags "${song.title}" failed: ${raw?['error']}',
        );
      } else {
        await invalidate(song.id);
      }
      return success;
    } on PlatformException catch (e) {
      LogService.warn(
        'ReplayGain',
        'removeReplayGainTags "${song.title}": ${e.code} – ${e.message}',
      );
      return false;
    }
  }

  /// Writes measured loudness for many songs in ONE native channel call.
  ///
  /// Batch counterpart of [writeReplayGain] (R-B, 1.5.21) used by
  /// [scanLibrary]: without it a library-wide "scan + write permanently" run
  /// pays a full MethodChannel round trip per song for the write itself — on
  /// a 1,000-song library that is ~1,000 cross-process calls of pure overhead
  /// stacked on top of the already-dominant PCM scan time.
  ///
  /// Every request must carry values measured by a prior scan; the native
  /// side re-validates each song's file identity before mutating
  /// (STALE_SCAN semantics preserved per song), and per-song success/error is
  /// kept so one bad file never fails the whole batch. Callers MUST
  /// pre-authorize write access for every song id via [requestBatchWriteAccess]
  /// first — songs that were not granted fail with WRITE_ACCESS_DENIED in
  /// their own result slot.
  ///
  /// Returns one bool per request, in the same order. Successful writes have
  /// their in-memory/prefs cache entries invalidated so the next [resolve]
  /// re-reads the fresh tags.
  static Future<List<bool>> writeReplayGainBatch(
    List<ReplayGainWriteRequest> requests,
  ) async {
    if (kIsWeb || requests.isEmpty) return const [];
    final payload = <Map<String, Object?>>[
      for (final r in requests)
        {
          'path': r.song.path,
          'songId': r.song.id,
          'trackGainDb': r.trackGainDb,
          'trackPeak': r.trackPeak,
          'integratedLufs': r.trackIntegratedLufs,
          'fileSize': r.expectedFileSize,
          'fileMtimeMs': r.expectedFileMtimeMs,
          'albumGainDb': r.albumGainDb,
          'albumPeak': r.albumPeak,
          'albumIntegratedLufs': r.albumIntegratedLufs,
        },
    ];
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'writeReplayGainBatch',
        payload,
      );
      final results = raw ?? const <Map<dynamic, dynamic>>[];
      // The native side always returns one result per request, but never treat
      // a short/null reply as success — pad with false so callers can't
      // mistake missing results for written songs.
      final ok = <bool>[];
      final toInvalidate = <int>[];
      for (var i = 0; i < requests.length; i++) {
        final r = i < results.length ? results[i] : null;
        final success = r?['success'] == true;
        ok.add(success);
        if (success) {
          final songId = (r?['songId'] as num?)?.toInt();
          if (songId != null) toInvalidate.add(songId);
        }
      }
      if (toInvalidate.isNotEmpty) {
        await Future.wait([for (final id in toInvalidate) invalidate(id)]);
      }
      return ok;
    } on PlatformException catch (e) {
      LogService.warn(
        'ReplayGain',
        'writeReplayGainBatch (${requests.length} songs): ${e.code} – ${e.message}',
      );
      return List.filled(requests.length, false);
    } on Object catch (e) {
      // Never let a non-PlatformException (channel closed, malformed payload,
      // etc.) reject this Future: callers run two batches under a shared
      // Future.wait, and one rejected future must not discard the other
      // batch's already-completed results.
      LogService.warn(
        'ReplayGain',
        'writeReplayGainBatch (${requests.length} songs): $e',
      );
      return List.filled(requests.length, false);
    }
  }

  /// Max requests per native batch channel call (1.5.23): keeps every message
  /// payload bounded (~40–50 KB) and lets a 2-way parallel pool keep both
  /// native write workers saturated instead of one giant 50/50 split that
  /// idles the faster worker at the tail.
  static const int _writeChunkSize = 250;

  /// Flushes [pending] via native batch tag-write calls; returns the number of
  /// songs whose write failed. Empty list → 0 without any channel call.
  ///
  /// Deduplicates by [LocalSong.id] first (a duplicated songId must never be
  /// written twice — let alone concurrently by two workers on the same file),
  /// then processes requests in fixed-size chunks (≤ [_writeChunkSize]) through
  /// a 2-way parallel pool that mirrors the two native write workers: both stay
  /// busy for large libraries, and every channel message payload stays bounded.
  static Future<int> _flushPendingWrites(
    List<ReplayGainWriteRequest> pending,
  ) async {
    if (pending.isEmpty) return 0;

    final seen = <int>{};
    final unique = <ReplayGainWriteRequest>[
      for (final r in pending)
        if (seen.add(r.song.id)) r,
    ];

    var failures = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < unique.length) {
        final start = next;
        final end = start + _writeChunkSize < unique.length
            ? start + _writeChunkSize
            : unique.length;
        next = end;
        final results = await writeReplayGainBatch(unique.sublist(start, end));
        failures += results.where((ok) => !ok).length;
      }
    }

    try {
      // Two concurrent channel calls → two native executor tasks → both write
      // workers run in parallel on different files (each write/verify cycle
      // uses its own per-song MediaStore fd). writeReplayGainBatch never
      // throws, so neither worker can take the other down.
      await Future.wait(<Future<void>>[worker(), worker()]);
    } on Object catch (e) {
      LogService.warn('ReplayGain', '_flushPendingWrites: $e');
    }
    return failures;
  }
}