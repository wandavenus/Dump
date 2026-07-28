import 'online_track.dart';

enum DownloadStatus { queued, downloading, finalizing, completed, failed, skipped }

enum DownloadErrorType { unknown, notFound, rateLimit, network, permission }

class DownloadItem {
  final String id;
  final OnlineTrack track;
  final String extensionId;
  final DownloadStatus status;
  final double progress;
  final double speedMBps;
  final String? filePath;
  final String? error;
  final DownloadErrorType? errorType;
  final String quality;
  final DateTime createdAt;

  const DownloadItem({
    required this.id,
    required this.track,
    required this.extensionId,
    required this.status,
    required this.progress,
    required this.speedMBps,
    this.filePath,
    this.error,
    this.errorType,
    required this.quality,
    required this.createdAt,
  });

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'] as String? ?? '',
      track: OnlineTrack.fromJson(_nullableObjectMap(json['track']) ?? const <String, dynamic>{}),
      extensionId: json['extensionId'] as String? ?? '',
      status: _decodeEnum(DownloadStatus.values, json['status'] as String?) ?? DownloadStatus.queued,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      speedMBps: (json['speedMBps'] as num?)?.toDouble() ?? 0,
      filePath: json['filePath'] as String?,
      error: json['error'] as String?,
      errorType: _decodeEnum(DownloadErrorType.values, json['errorType'] as String?),
      quality: json['quality'] as String? ?? 'LOSSLESS',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'track': track.toJson(),
        'extensionId': extensionId,
        'status': status.name,
        'progress': progress,
        'speedMBps': speedMBps,
        if (filePath != null) 'filePath': filePath,
        if (error != null) 'error': error,
        if (errorType != null) 'errorType': errorType!.name,
        'quality': quality,
        'createdAt': createdAt.toIso8601String(),
      };

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    double? speedMBps,
    String? filePath,
    String? error,
    DownloadErrorType? errorType,
  }) {
    return DownloadItem(
      id: id,
      track: track,
      extensionId: extensionId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speedMBps: speedMBps ?? this.speedMBps,
      filePath: filePath ?? this.filePath,
      error: error ?? this.error,
      errorType: errorType ?? this.errorType,
      quality: quality,
      createdAt: createdAt,
    );
  }
}

T? _decodeEnum<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Map<String, dynamic>? _nullableObjectMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}
