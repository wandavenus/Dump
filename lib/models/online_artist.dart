class OnlineArtist {
  final String id;
  final String name;
  final String? imageUrl;
  final String? description;
  final String source;

  const OnlineArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.description,
    required this.source,
  });

  factory OnlineArtist.fromJson(Map<String, dynamic> json) {
    return OnlineArtist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Artist',
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      source: json['source'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (description != null) 'description': description,
        'source': source,
      };
}
