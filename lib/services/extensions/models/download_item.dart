import 'online_track.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.track,
    required this.status,
    required this.progress,
    this.filePath,
    this.error,
    this.speedBytesPerSecond = 0,
  });
  final String id;
  final OnlineTrack track;
  final DownloadStatus status;
  final double progress;
  final String? filePath, error;
  final double speedBytesPerSecond;
  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? filePath,
    String? error,
    double? speedBytesPerSecond,
  }) => DownloadItem(
    id: id,
    track: track,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    filePath: filePath ?? this.filePath,
    error: error,
    speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
  );
  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    final trackJson = (j['track'] as Map).cast<String, dynamic>();
    return DownloadItem(
      id: j['id'].toString(),
      track: OnlineTrack.fromJson(
        trackJson,
        trackJson['extensionId'].toString(),
      ),
      status: DownloadStatus.values.byName(j['status'].toString()),
      progress: (j['progress'] as num).toDouble(),
      filePath: j['filePath']?.toString(),
      error: j['error']?.toString(),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'track': track.toJson(),
    'status': status.name,
    'progress': progress,
    'filePath': filePath,
    'error': error,
  };
}
