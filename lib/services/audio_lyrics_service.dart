import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lyric_line.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioLyricsService {
  static final Map<String, List<LyricLine>> _cache = {};

  static Future<List<LyricLine>> fetchEmbeddedLyrics(int songId, String title, String artist) async {
    final key = '$artist|$title';

    if (_cache.containsKey(key)) return _cache[key]!;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(key);
    if (stored != null && stored.isNotEmpty) {
      final lines = stored.map((s) {
        final parts = s.split('|');
        final timestamp = Duration(milliseconds: int.tryParse(parts[0]) ?? 0);
        final text = parts.length > 1 ? parts[1] : '';
        return LyricLine(timestamp: timestamp, text: text);
      }).toList();
      _cache[key] = lines;
      return lines;
    }

    // Read embedded lyrics from the file using on_audio_query
    final audioQuery = OnAudioQuery();
    final song = (await audioQuery.querySongs()).firstWhere((s) => s.id == songId);
    final lyricsRaw = song.lyrics ?? ''; // plugin dependent, some fields might be different

    if (lyricsRaw.isEmpty) return [];

    final lines = lyricsRaw.split('\n').map((line) {
      // naive parser: optional timestamp in ms | text
      final match = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)').firstMatch(line);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = double.tryParse(match.group(2) ?? '0') ?? 0;
        final text = (match.group(3) ?? '').trim();
        return LyricLine(timestamp: Duration(milliseconds: ((minutes*60+seconds)*1000).round()), text: text);
      } else {
        return LyricLine(timestamp: Duration.zero, text: line);
      }
    }).toList();

    // Save to cache and SharedPreferences
    _cache[key] = lines;
    final store = lines.map((l) => '${l.timestamp.inMilliseconds}|${l.text}').toList();
    await prefs.setStringList(key, store);

    return lines;
  }
}