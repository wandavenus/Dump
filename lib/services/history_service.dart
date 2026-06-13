import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_song.dart';

class HistoryService {
  static const _recentKey = 'recently_played';
  static const _playCountKey = 'play_count';
  static const _artistPlayCountKey = 'artist_play_count';

  static Future<void> trackPlay(LocalSong song) async {
    final prefs = await SharedPreferences.getInstance();

    final recent = prefs.getStringList(_recentKey) ?? [];
    recent.remove(song.id.toString());
    recent.insert(0, song.id.toString());

    if (recent.length > 20) {
      recent.removeRange(20, recent.length);
    }

    await prefs.setStringList(_recentKey, recent);

    final playCounts = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(_playCountKey) ?? '{}'),
    );

    playCounts[song.id.toString()] =
        (playCounts[song.id.toString()] ?? 0) + 1;

    await prefs.setString(_playCountKey, jsonEncode(playCounts));

    final artistCounts = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(_artistPlayCountKey) ?? '{}'),
    );

    artistCounts[song.artist] =
        (artistCounts[song.artist] ?? 0) + 1;

    await prefs.setString(
      _artistPlayCountKey,
      jsonEncode(artistCounts),
    );
  }

  static Future<List<int>> getRecentlyPlayedIds() async {
    final prefs = await SharedPreferences.getInstance();

    return (prefs.getStringList(_recentKey) ?? [])
        .map(int.parse)
        .toList();
  }

  static Future<Map<String, dynamic>> getPlayCounts() async {
    final prefs = await SharedPreferences.getInstance();

    return Map<String, dynamic>.from(
      jsonDecode(prefs.getString(_playCountKey) ?? '{}'),
    );
  }

  static Future<Map<String, dynamic>> getArtistPlayCounts() async {
    final prefs = await SharedPreferences.getInstance();

    return Map<String, dynamic>.from(
      jsonDecode(prefs.getString(_artistPlayCountKey) ?? '{}'),
    );
  }
}
