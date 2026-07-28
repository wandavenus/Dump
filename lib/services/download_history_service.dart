import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DownloadHistoryService {
  static const _historyKey = 'hybrid_download_history_v1';

  final SharedPreferences _preferences;

  DownloadHistoryService(this._preferences);

  Future<void> addEntry(DownloadHistoryEntry entry) async {
    final entries = await queryHistory();
    final updated = [
      entry,
      ...entries.where((existing) => existing.id != entry.id && existing.filePath != entry.filePath),
    ];
    await _writeEntries(updated);
  }

  Future<List<DownloadHistoryEntry>> queryHistory({int? limit, int? offset, String? filter}) async {
    final normalizedFilter = filter?.trim().toLowerCase();
    var entries = _readEntries();

    if (normalizedFilter != null && normalizedFilter.isNotEmpty) {
      entries = entries.where((entry) => entry.matches(normalizedFilter)).toList(growable: false);
    }

    entries.sort((left, right) => right.downloadedAt.compareTo(left.downloadedAt));

    final start = offset ?? 0;
    if (start >= entries.length) return const <DownloadHistoryEntry>[];
    final end = limit == null ? entries.length : (start + limit).clamp(0, entries.length);
    return entries.sublist(start, end);
  }

  Future<bool> isDownloaded(String trackId) async {
    return _readEntries().any((entry) => entry.trackId == trackId && entry.filePath.isNotEmpty);
  }

  Future<bool> isDownloadedByIsrc(String isrc) async {
    final normalized = isrc.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _readEntries().any((entry) => entry.isrc?.toLowerCase() == normalized && entry.filePath.isNotEmpty);
  }

  Future<DownloadHistoryEntry?> findByFilePath(String path) async {
    for (final entry in _readEntries()) {
      if (entry.filePath == path) return entry;
    }
    return null;
  }

  Future<void> removeEntry(String id) async {
    await _writeEntries(_readEntries().where((entry) => entry.id != id).toList(growable: false));
  }

  Future<void> clearAll() async {
    await _preferences.remove(_historyKey);
  }

  List<DownloadHistoryEntry> _readEntries() {
    final rawEntries = _preferences.getStringList(_historyKey) ?? const <String>[];
    return rawEntries.map((raw) => DownloadHistoryEntry.fromJson(_decodeRequiredMap(jsonDecode(raw)))).toList();
  }

  Future<void> _writeEntries(List<DownloadHistoryEntry> entries) {
    return _preferences.setStringList(
      _historyKey,
      entries.map((entry) => jsonEncode(entry.toJson())).toList(growable: false),
    );
  }
}

class DownloadHistoryEntry {
  final String id;
  final String trackId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? coverUrl;
  final String filePath;
  final String quality;
  final String format;
  final String extensionId;
  final DateTime downloadedAt;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? isrc;
  final int? fileSizeBytes;
  final bool hasLyrics;
  final bool hasReplayGain;
  final String? error;
  final String? errorType;

  const DownloadHistoryEntry({
    required this.id,
    required this.trackId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.coverUrl,
    required this.filePath,
    required this.quality,
    required this.format,
    required this.extensionId,
    required this.downloadedAt,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.isrc,
    this.fileSizeBytes,
    this.hasLyrics = false,
    this.hasReplayGain = false,
    this.error,
    this.errorType,
  });

  bool matches(String normalizedFilter) {
    return trackName.toLowerCase().contains(normalizedFilter) ||
        artistName.toLowerCase().contains(normalizedFilter) ||
        albumName.toLowerCase().contains(normalizedFilter) ||
        extensionId.toLowerCase().contains(normalizedFilter);
  }

  factory DownloadHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DownloadHistoryEntry(
      id: json['id'] as String? ?? '',
      trackId: json['track_id'] as String? ?? '',
      trackName: json['track_name'] as String? ?? '',
      artistName: json['artist_name'] as String? ?? '',
      albumName: json['album_name'] as String? ?? '',
      coverUrl: json['cover_url'] as String?,
      filePath: json['file_path'] as String? ?? '',
      quality: json['quality'] as String? ?? '',
      format: json['format'] as String? ?? '',
      extensionId: json['extension_id'] as String? ?? '',
      downloadedAt: DateTime.tryParse(json['downloaded_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      bitDepth: (json['bit_depth'] as num?)?.toInt(),
      sampleRate: (json['sample_rate'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      isrc: json['isrc'] as String?,
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      hasLyrics: json['has_lyrics'] as bool? ?? false,
      hasReplayGain: json['has_replaygain'] as bool? ?? false,
      error: json['error'] as String?,
      errorType: json['error_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'track_id': trackId,
    'track_name': trackName,
    'artist_name': artistName,
    'album_name': albumName,
    if (coverUrl != null) 'cover_url': coverUrl,
    'file_path': filePath,
    'quality': quality,
    'format': format,
    'extension_id': extensionId,
    'downloaded_at': downloadedAt.toIso8601String(),
    if (bitDepth != null) 'bit_depth': bitDepth,
    if (sampleRate != null) 'sample_rate': sampleRate,
    if (bitrate != null) 'bitrate': bitrate,
    if (isrc != null) 'isrc': isrc,
    if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
    'has_lyrics': hasLyrics,
    'has_replaygain': hasReplayGain,
    if (error != null) 'error': error,
    if (errorType != null) 'error_type': errorType,
  };
}

Map<String, dynamic> _decodeRequiredMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  throw FormatException('Expected history entry map, got ${value.runtimeType}.');
}
