import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyric_line.dart';

class LyricsService {
  static final Map<String, List<LyricLine>> _cache = {};

  static Future<List<LyricLine>> fetchLyrics({
    required String title,
    required String artist,
  }) async {
    final key = '$artist|$title';
    final prefKey = 'lyrics_$key';

    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final savedLyrics = prefs.getString(prefKey);
      if (savedLyrics != null && savedLyrics.isNotEmpty) {
        final lyrics = parseLrc(savedLyrics);
        _cache[key] = lyrics;
        return lyrics;
      }

      final normalizedArtist = artist.split(',').first.trim();
      final normalizedTitle =
          title.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

      Future<String?> search(String track, String artistName) async {
        final uri = Uri.parse(
          'https://lrclib.net/api/search?track_name=${Uri.encodeComponent(track)}&artist_name=${Uri.encodeComponent(artistName)}',
        );

        final response = await http.get(
          uri,
          headers: {
            'User-Agent': 'MusicPlayer/1.0',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode != 200) {
          return null;
        }

        final data = jsonDecode(response.body);

        if (data is! List || data.isEmpty) {
          return null;
        }

        final first = data.first;
        final syncedLyrics =
            (first['syncedLyrics'] ?? first['lyrics'] ?? '') as String;

        if (syncedLyrics.isEmpty) {
          return null;
        }

        return syncedLyrics;
      }

      String? rawLyrics =
          await search(normalizedTitle, normalizedArtist);

      rawLyrics ??= await search(title, artist);

      if (rawLyrics == null || rawLyrics.isEmpty) {
        return [];
      }

      await prefs.setString(prefKey, rawLyrics);

      final lyrics = parseLrc(rawLyrics);
      _cache[key] = lyrics;
      return lyrics;
    } catch (_) {
      return [];
    }
  }

  static List<LyricLine> parseLrc(String lrc) {
    final result = <LyricLine>[];

    for (final line in lrc.split('\n')) {
      final match = RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\](.*)$')
          .firstMatch(line.trim());

      if (match == null) continue;

      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = double.tryParse(match.group(2) ?? '') ?? 0;
      final text = (match.group(3) ?? '').trim();

      result.add(
        LyricLine(
          timestamp: Duration(
            milliseconds: (((minutes * 60) + seconds) * 1000).round(),
          ),
          text: text,
        ),
      );
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return result;
  }
}
