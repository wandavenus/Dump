class LocalSong {
  final int id;
  final String title;
  final String artist;
  final String path;
  final String? contentUri;
  final String album;
  final int albumId;
  final String? artworkUri;
  final Duration duration;

  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    this.contentUri,
    required this.album,
    required this.albumId,
    this.artworkUri,
    required this.duration,
  });

  factory LocalSong.fromMap(Map<dynamic, dynamic> map) {
    return LocalSong(
      id: _toInt(map['id']),
      title: map['title'] ?? 'Unknown Title',
      artist: map['artist'] ?? 'Unknown Artist',
      path: map['path'] ?? '',
      contentUri: map['contentUri'],
      album: map['album'] ?? 'Unknown Album',
      albumId: _toInt(map['albumId']),
      artworkUri: map['artworkUri'],
      duration: Duration(
        milliseconds: _toInt(map['duration']),
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'path': path,
      'contentUri': contentUri,
      'album': album,
      'albumId': albumId,
      'artworkUri': artworkUri,
      'duration': duration.inMilliseconds,
    };
  }
}
