class LocalSong {
  final int id;
  final String title;
  final String artist;
  final String path;
  final String album;
  final int albumId;
  final Duration duration;

  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.album,
    required this.albumId,
    required this.duration,
  });

  factory LocalSong.fromMap(Map<dynamic, dynamic> map) {
    return LocalSong(
      id: map['id'] ?? 0,
      title: map['title'] ?? 'Unknown Title',
      artist: map['artist'] ?? 'Unknown Artist',
      path: map['path'] ?? '',
      album: map['album'] ?? 'Unknown Album',
      albumId: map['albumId'] ?? 0,
      duration: Duration(
        milliseconds: map['duration'] ?? 0,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'path': path,
      'album': album,
      'albumId': albumId,
      'duration': duration.inMilliseconds,
    };
  }
}
