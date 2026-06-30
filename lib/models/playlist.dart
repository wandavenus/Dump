import 'dart:convert';

enum SmartPlaylistType { favorites, recentlyPlayed, mostPlayed }

class Playlist {
  final String id;
  final String name;
  final List<int> songIds;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
  });

  Playlist copyWith({String? name, List<int>? songIds}) => Playlist(
    id: id,
    name: name ?? this.name,
    songIds: songIds ?? this.songIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: (json['songIds'] as List).map((e) => e as int).toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
  );

  static String encodeList(List<Playlist> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());

  static List<Playlist> decodeList(String raw) =>
      (jsonDecode(raw) as List)
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
}
