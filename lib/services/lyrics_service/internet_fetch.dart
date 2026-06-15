part of '../lyrics_service.dart';

// ─── Internet lyrics fetch (lrclib.net) ───────────────────────────────────────
//
//  Library-level functions extracted from LyricsService.
//  Uses SharedPreferences as a local cache for internet-sourced lyrics
//  (separate from the in-memory LyricsService._cache).
// ─────────────────────────────────────────────────────────────────────────────

Future<List<LyricLine>> _lyricsFromInternet(String title, String artist) async {
  final prefKey = 'lyrics_${artist.trim()}|${title.trim()}';
  try {
    final prefs  = await SharedPreferences.getInstance();
    final cached = prefs.getString(prefKey);
    if (cached != null && cached.isNotEmpty) return LyricsService.parseLrc(cached);

    final normalArtist = artist.split(',').first.trim();
    final normalTitle  = title.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

    String? raw = await _lyricsSearchLrcLib(normalTitle, normalArtist);
    raw ??= await _lyricsSearchLrcLib(title, artist);
    if (raw == null || raw.isEmpty) return [];

    await prefs.setString(prefKey, raw);
    LogService.log('Lyrics', 'Internet: $title');
    return LyricsService.parseLrc(raw);
  } catch (e) {
    LogService.warn('Lyrics', 'Internet error: $e');
    return [];
  }
}

Future<String?> _lyricsSearchLrcLib(String track, String artist) async {
  final uri = Uri.parse(
    'https://lrclib.net/api/search'
    '?track_name=${Uri.encodeComponent(track)}'
    '&artist_name=${Uri.encodeComponent(artist)}',
  );
  final response = await http
      .get(uri, headers: {'User-Agent': 'MusicPlayer/1.0'})
      .timeout(const Duration(seconds: 8));
  if (response.statusCode != 200) return null;
  final data = jsonDecode(response.body);
  if (data is! List || data.isEmpty) return null;
  final synced =
      (data.first['syncedLyrics'] ?? data.first['lyrics'] ?? '') as String;
  return synced.isEmpty ? null : synced;
}
