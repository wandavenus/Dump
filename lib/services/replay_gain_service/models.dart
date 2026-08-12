part of '../replay_gain_service.dart';

// ── Internal scan + batch-write types ──────────────────────────────────────────

/// Private result of [_scanTrackResult]: the cached [LoudnessData] plus the
/// raw LUFS value and file identity needed to persist tags later.
class _TrackScan {
  const _TrackScan({
    required this.data,
    required this.integratedLufs,
    required this.identity,
  });

  final LoudnessData data;
  final double? integratedLufs;
  final _ReplayGainFileIdentity identity;
}

/// One song's tag-write request for [ReplayGainService.writeReplayGainBatch].
class ReplayGainWriteRequest {
  const ReplayGainWriteRequest({
    required this.song,
    required this.trackGainDb,
    required this.trackPeak,
    required this.trackIntegratedLufs,
    this.expectedFileSize,
    this.expectedFileMtimeMs,
    this.albumGainDb,
    this.albumPeak,
    this.albumIntegratedLufs,
  });

  final LocalSong song;
  final double trackGainDb;
  final double trackPeak;
  final double trackIntegratedLufs;
  final int? expectedFileSize;
  final int? expectedFileMtimeMs;
  final double? albumGainDb;
  final double? albumPeak;
  final double? albumIntegratedLufs;
}

// ── Album scan result types ────────────────────────────────────────────────────

/// Per-track loudness measurement returned as part of an [AlbumScanResult].
class TrackLoudnessResult {
  const TrackLoudnessResult({
    required this.song,
    required this.trackGainDb,
    required this.trackPeak,
    required this.trackIntegratedLufs,
  });

  final LocalSong song;
  final double trackGainDb;
  final double? trackPeak;
  final double? trackIntegratedLufs;
}

/// Result of a [ReplayGainService.removeReplayGainFromLibrary] call.
class RemoveRgResult {
  const RemoveRgResult({required this.removed, required this.failed});

  final int removed;
  final int failed;
}

/// Result of a [ReplayGainService.scanAlbum] call.
class AlbumScanResult {
  const AlbumScanResult({
    required this.trackResults,
    required this.albumGainDb,
    required this.albumPeak,
    required this.albumIntegratedLufs,
    required this.failedPaths,
  });

  /// Keyed by song id.
  final Map<int, TrackLoudnessResult> trackResults;
  final double albumGainDb;
  final double? albumPeak;
  final double? albumIntegratedLufs;
  final List<String> failedPaths;

  bool get hasData => trackResults.isNotEmpty;
}

// ── Batch scan progress snapshot ──────────────────────────────────────────────

/// Immutable state for a [ReplayGainService.scanLibrary] run.
class BatchScanProgress {
  const BatchScanProgress({
    this.done = 0,
    this.total = 0,
    this.failed = 0,
    this.running = false,
    this.cancelled = false,
    this.currentTitle = '',
  });

  /// Songs processed so far (successes + failures combined).
  final int done;

  /// Total songs queued for this run.
  final int total;

  /// Songs that failed to decode.
  final int failed;

  /// Whether a scan is currently in progress.
  final bool running;

  /// Whether the last scan ended due to user cancellation.
  final bool cancelled;

  /// Title of the song currently being scanned (empty when idle).
  final String currentTitle;

  int get succeeded => done - failed;

  /// `true` when no scan has started yet since app launch.
  bool get idle => !running && total == 0;

  /// `true` after a scan completes (with or without cancellation).
  bool get finished => !running && total > 0;

  BatchScanProgress copyWith({
    int? done,
    int? total,
    int? failed,
    bool? running,
    bool? cancelled,
    String? currentTitle,
  }) => BatchScanProgress(
    done: done ?? this.done,
    total: total ?? this.total,
    failed: failed ?? this.failed,
    running: running ?? this.running,
    cancelled: cancelled ?? this.cancelled,
    currentTitle: currentTitle ?? this.currentTitle,
  );
}
