part of '../loudness_cache.dart';

/// Persists loudness analysis results across app launches.
///
/// Keys are `"$filePath:$lastModifiedMs"` so the cache is automatically
/// invalidated whenever a file is replaced or re-encoded.  Capacity is
/// capped at [_maxEntries] using a simple FIFO eviction strategy.
class LoudnessCache {
  LoudnessCache._();

  static const String _prefKey  = 'loudness_cache_v1';
  static const int    _maxEntries = 1000;

  static Map<String, Map<String, dynamic>>? _memory;

  // ── Read / Write ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> get(String filePath) async {
    final map = await _load();
    final key = await _keyFor(filePath);
    if (key == null) return null;
    return map[key];
  }

  static Future<void> put(String filePath, Map<String, dynamic> data) async {
    final key = await _keyFor(filePath);
    if (key == null) return;
    final map = await _load();
    map[key] = data;

    // FIFO eviction
    if (map.length > _maxEntries) {
      final oldest = map.keys.first;
      map.remove(oldest);
    }

    await _save(map);
    LogService.log('LoudnessCache', 'Stored → $key');
  }

  static Future<void> clear() async {
    _memory = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    LogService.log('LoudnessCache', 'Cleared');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<String?> _keyFor(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) return null;
      final modified = (await f.lastModified()).millisecondsSinceEpoch;
      return '$filePath:$modified';
    } catch (_) {
      // Web or inaccessible – fall back to path only
      return filePath;
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    if (_memory != null) return _memory!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw == null) {
        _memory = {};
        return _memory!;
      }
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _memory = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      _memory = {};
    }
    return _memory!;
  }

  static Future<void> _save(Map<String, Map<String, dynamic>> map) async {
    _memory = map;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, json.encode(map));
    } catch (e) {
      LogService.warn('LoudnessCache', 'Save failed: $e');
    }
  }
}
