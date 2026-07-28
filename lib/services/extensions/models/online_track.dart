class OnlineTrack {
  const OnlineTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.extensionId,
    this.artwork,
    this.quality,
    this.durationMs,
    this.providerId,
    this.raw = const {},
  });

  final String id, title, artist, album, extensionId;
  final String? artwork, quality, providerId;
  final int? durationMs;
  final Map<String, dynamic> raw;

  factory OnlineTrack.fromJson(Map<String, dynamic> json, String extensionId) {
    final artists = json['artists'];
    final artist = artists is List
        ? artists.map((e) => e.toString()).where((e) => e.isNotEmpty).join(', ')
        : (json['artist'] ?? json['artist_name'] ?? '').toString();
    final images = json['images'];
    String? image;
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      image = first is Map ? first['url']?.toString() : first?.toString();
    }
    return OnlineTrack(
      id: (json['id'] ?? json['url'] ?? json['track_id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? '').toString(),
      artist: artist,
      album: (json['album'] ?? json['album_name'] ?? '').toString(),
      artwork: (json['artwork'] ?? json['cover_url'] ?? image)?.toString(),
      quality: (json['quality'] ?? json['audio_quality'])?.toString(),
      durationMs: _intOrNull(json['duration_ms'] ?? json['durationMs']),
      providerId: (json['provider_id'] ?? json['providerId'] ?? extensionId)
          .toString(),
      extensionId: extensionId,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => {
    ...raw,
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'extensionId': extensionId,
    'provider_id': providerId ?? extensionId,
    'artwork': artwork,
    'quality': quality,
    'duration_ms': durationMs,
  };

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
