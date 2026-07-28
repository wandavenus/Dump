class OnlineTrack {
  final String id;
  final String name;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String? artistId;
  final String? albumId;
  final String? coverUrl;
  final String? isrc;
  final String? previewUrl;
  final int durationMs;
  final int? trackNumber;
  final int? discNumber;
  final String? releaseDate;
  final String? audioQuality;
  final String? explicit;
  final String source;

  const OnlineTrack({
    required this.id,
    required this.name,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    this.artistId,
    this.albumId,
    this.coverUrl,
    this.isrc,
    this.previewUrl,
    required this.durationMs,
    this.trackNumber,
    this.discNumber,
    this.releaseDate,
    this.audioQuality,
    this.explicit,
    required this.source,
  });

  factory OnlineTrack.fromJson(Map<String, dynamic> json) {
    return OnlineTrack(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Title',
      artistName: json['artistName'] as String? ?? 'Unknown Artist',
      albumName: json['albumName'] as String? ?? 'Unknown Album',
      albumArtist: json['albumArtist'] as String?,
      artistId: json['artistId'] as String?,
      albumId: json['albumId'] as String?,
      coverUrl: json['coverUrl'] as String?,
      isrc: json['isrc'] as String?,
      previewUrl: json['previewUrl'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      releaseDate: json['releaseDate'] as String?,
      audioQuality: json['audioQuality'] as String?,
      explicit: json['explicit'] as String?,
      source: json['source'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artistName': artistName,
      'albumName': albumName,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (artistId != null) 'artistId': artistId,
      if (albumId != null) 'albumId': albumId,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (isrc != null) 'isrc': isrc,
      if (previewUrl != null) 'previewUrl': previewUrl,
      'durationMs': durationMs,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (discNumber != null) 'discNumber': discNumber,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (audioQuality != null) 'audioQuality': audioQuality,
      if (explicit != null) 'explicit': explicit,
      'source': source,
    };
  }
}
