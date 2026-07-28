class OnlineTrack {
  const OnlineTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.extensionId,
    this.artwork,
    this.quality,
  });
  final String id, title, artist, album, extensionId;
  final String? artwork, quality;
  factory OnlineTrack.fromJson(Map<String, dynamic> json, String extensionId) =>
      OnlineTrack(
        id: (json['id'] ?? json['url'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        artist: (json['artist'] ?? '').toString(),
        album: (json['album'] ?? '').toString(),
        artwork: json['artwork']?.toString(),
        quality: json['quality']?.toString(),
        extensionId: extensionId,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'extensionId': extensionId,
    'artwork': artwork,
    'quality': quality,
  };
}
