import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_song.dart';

class HistoryService {
  static const _recentKey = 'recently_played';
  static const _playCountKey = 'play_count';
  static const _artistPlayCountKey = 'artist_play_count';

  // Cached SharedPreferences instance — populated once by [warmUp] so all
  // subsequent reads/writes skip the getInstance() round-trip.
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(decoded);
  }

  // ── Startup warm-up cache ──────────────────────────────────────────────────
  // Populated once by [warmUp] (called alongside ArtworkRepository.warmUp and
  // MediaStoreService.warmUp in main()). UI widgets read the sync getters in
  // State.initState so the first frame renders content instead of a spinner.
  //
  // Write-through strategy: [trackPlay] updates these in-memory values after
  // every successful write, so the caches are always fresh and never nulled
  // mid-session. [getRecentlyPlayedIds] / [getArtistPlayCounts] also refresh
  // the cache on every fetch, keeping it in sync with SharedPreferences.

  static List<int>? _cachedRecentIds;
  static Map<String, dynamic>? _cachedArtistCounts;

  /// Synchronous snapshot of recently-played song IDs. Non-null after [warmUp].
  static List<int>? get cachedRecentIds => _cachedRecentIds;

  /// Synchronous snapshot of artist play counts. Non-null after [warmUp].
  static Map<String, dynamic>? get cachedArtistCounts => _cachedArtistCounts;

  /// Loads recently-played IDs and artist play counts from SharedPreferences
  /// into memory. Call once during app startup (alongside the other warm-ups)
  /// before [runApp] so the sync getters are ready for the first frame.
  static Future<void> warmUp() async {
    try {
      final prefs = await _getPrefs();
      // D1 fix: same tolerant pattern as [getRecentlyPlayedIds] — a corrupt /
      // legacy entry must not abort warm-up (the F6 fix already uses tryParse).
      _cachedRecentIds = (prefs.getStringList(_recentKey) ?? [])
          .map(int.tryParse)
          .whereType<int>()
          .toList(growable: false);
      _cachedArtistCounts = _decodeMap(
        prefs.getString(_artistPlayCountKey) ?? '{}',
      );
    } on Exception catch (_) {
      // Best-effort — failed warm-up just means the first frame falls back
      // to the async path (same behaviour as before this optimisation).
    }
  }

  static Future<void> trackPlay(LocalSong song) async {
    final prefs = await _getPrefs();

    // ── Compute all values first, then flush in parallel ─────────────────────

    // Recently played
    final recent = prefs.getStringList(_recentKey) ?? [];
    recent.remove(song.id.toString());
    recent.insert(0, song.id.toString());
    if (recent.length > 20) recent.removeRange(20, recent.length);

    // Song play count
    final playCounts = _decodeMap(prefs.getString(_playCountKey) ?? '{}');
    playCounts[song.id.toString()] =
        (playCounts[song.id.toString()] as int? ?? 0) + 1;

    // Artist play count
    final artistCounts = _decodeMap(
      prefs.getString(_artistPlayCountKey) ?? '{}',
    );
    artistCounts[song.artist] = (artistCounts[song.artist] as int? ?? 0) + 1;

    // Flush all three keys to SharedPreferences in parallel.
    await Future.wait([
      prefs.setStringList(_recentKey, recent),
      prefs.setString(_playCountKey, jsonEncode(playCounts)),
      prefs.setString(_artistPlayCountKey, jsonEncode(artistCounts)),
    ]);

    // Write-through: keep in-memory caches in sync so sync getters stay valid.
    // D1 fix: entries are always written by [trackPlay] as integers, but a
    // corrupt/legacy value must be dropped (tryParse) instead of throwing —
    // matching [getRecentlyPlayedIds].
    _cachedRecentIds = recent
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    _cachedArtistCounts = artistCounts;
  }

  static Future<List<int>> getRecentlyPlayedIds() async {
    final prefs = await _getPrefs();
    // F6 fix: drop unparseable entries instead of throwing — a corrupt/legacy
    // prefs value must not crash the home sections that call this.
    final ids = (prefs.getStringList(_recentKey) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    // Keep in-memory cache current so sync getter stays valid after any caller.
    _cachedRecentIds = ids;
    return ids;
  }

  static Future<Map<String, dynamic>> getPlayCounts() async {
    final prefs = await _getPrefs();
    return _decodeMap(prefs.getString(_playCountKey) ?? '{}');
  }

  static Future<Map<String, dynamic>> getArtistPlayCounts() async {
    final prefs = await _getPrefs();
    final counts = _decodeMap(prefs.getString(_artistPlayCountKey) ?? '{}');
    // Keep in-memory cache current.
    _cachedArtistCounts = counts;
    return counts;
  }
}
