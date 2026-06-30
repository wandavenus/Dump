class LocalSong {
  final int id;
  final String title;
  final String artist;
  final String path;
  final String album;
  final int albumId;
  final String? artworkUri;
  final Duration duration;

  // Extended fields — populated from MediaStore when available.
  // null means the tag is absent in the file or API level is too old.
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String? albumArtist;
  final String? genre;
  final int? bitrate; // bits/s — MediaStore API 31+
  final int? sampleRate; // Hz    — MediaStore API 31+

  const LocalSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.album,
    required this.albumId,
    this.artworkUri,
    required this.duration,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.albumArtist,
    this.genre,
    this.bitrate,
    this.sampleRate,
  });

  factory LocalSong.fromMap(Map<dynamic, dynamic> map) {
    return LocalSong(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      path: map['path'] as String? ?? '',
      album: map['album'] as String? ?? 'Unknown Album',
      albumId: (map['albumId'] as num?)?.toInt() ?? 0,
      artworkUri: map['artworkUri'] as String?,
      duration: Duration(milliseconds: (map['duration'] as num?)?.toInt() ?? 0),
      year: (map['year'] as num?)?.toInt(),
      trackNumber: (map['trackNumber'] as num?)?.toInt(),
      discNumber: (map['discNumber'] as num?)?.toInt(),
      albumArtist: map['albumArtist'] as String?,
      genre: map['genre'] as String?,
      bitrate: (map['bitrate'] as num?)?.toInt(),
      sampleRate: (map['sampleRate'] as num?)?.toInt(),
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
      'artworkUri': artworkUri,
      'duration': duration.inMilliseconds,
      if (year != null) 'year': year,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (discNumber != null) 'discNumber': discNumber,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (genre != null) 'genre': genre,
      if (bitrate != null) 'bitrate': bitrate,
      if (sampleRate != null) 'sampleRate': sampleRate,
    };
  }

  LocalSong copyWith({
    int? id,
    String? title,
    String? artist,
    String? path,
    String? album,
    int? albumId,
    String? artworkUri,
    Duration? duration,
    int? year,
    int? trackNumber,
    int? discNumber,
    String? albumArtist,
    String? genre,
    int? bitrate,
    int? sampleRate,
  }) {
    return LocalSong(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      path: path ?? this.path,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      artworkUri: artworkUri ?? this.artworkUri,
      duration: duration ?? this.duration,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }
}
