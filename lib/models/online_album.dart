class OnlineAlbum {
  final String id;
  final String name;
  final String artistName;
  final String? artistId;
  final String? coverUrl;
  final String? releaseDate;
  final int? trackCount;
  final String source;

  const OnlineAlbum({
    required this.id,
    required this.name,
    required this.artistName,
    this.artistId,
    this.coverUrl,
    this.releaseDate,
    this.trackCount,
    required this.source,
  });

  factory OnlineAlbum.fromJson(Map<String, dynamic> json) {
    return OnlineAlbum(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Album',
      artistName: json['artistName'] as String? ?? 'Unknown Artist',
      artistId: json['artistId'] as String?,
      coverUrl: json['coverUrl'] as String?,
      releaseDate: json['releaseDate'] as String?,
      trackCount: (json['trackCount'] as num?)?.toInt(),
      source: json['source'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artistName': artistName,
        if (artistId != null) 'artistId': artistId,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (releaseDate != null) 'releaseDate': releaseDate,
        if (trackCount != null) 'trackCount': trackCount,
        'source': source,
      };
}
