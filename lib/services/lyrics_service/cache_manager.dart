import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'lrc_parser.dart';
import 'provider.dart';
import 'quality.dart';

/// Cache dua-lapis (memory + disk) untuk hasil lirik.
///
/// TTL disk: 30 hari.
/// Key: dibangun dari artist + title + album + durationMs.
class LyricsCacheManager {
  static final LyricsCacheManager instance = LyricsCacheManager._();
  LyricsCacheManager._();

  static const _prefixV2 = 'lyrics_v2_';
  static const _ttlMs = 30 * 24 * 60 * 60 * 1000; // 30 hari

  // ── Memory cache ──────────────────────────────────────────────────────────
  final Map<String, _CacheEntry> _mem = {};

  // Kunci yang baru-baru ini gagal dicari — hindari re-request selama 1 jam.
  final Map<String, int> _failedAtMs = {};
  static const _failedTtlMs = 60 * 60 * 1000; // 1 jam

  // ─────────────────────────────────────────────────────────────────────────

  /// Ambil dari memory cache. Return null jika tidak ada / expired.
  LyricsProviderResult? getMemory(String key) {
    final entry = _mem[key];
    if (entry == null) return null;
    if (DateTime.now().millisecondsSinceEpoch - entry.cachedAtMs > _ttlMs) {
      _mem.remove(key);
      return null;
    }
    return entry.result;
  }

  /// Simpan ke memory cache.
  void putMemory(String key, LyricsProviderResult result) {
    _mem[key] = _CacheEntry(result, DateTime.now().millisecondsSinceEpoch);
  }

  /// Ambil dari disk cache (SharedPreferences). Return null jika tidak ada / expired.
  Future<LyricsProviderResult?> getDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefixV2$key');
      if (raw == null) return null;

      final Map<String, dynamic> map = jsonDecode(raw);
      final int cachedAt = (map['cachedAt'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt > _ttlMs) {
        await prefs.remove('$_prefixV2$key');
        return null;
      }

      final String lrc = map['lrc'] as String? ?? '';
      if (lrc.isEmpty) return null;

      final quality = lyricsQualityFromJson(map['quality'] as String?);
      final providerName = map['provider'] as String? ?? 'Cache';
      final isInternet = map['isInternet'] as bool? ?? true;

      final lines = LrcParser.parseLrc(lrc);
      if (lines.isEmpty) return null;

      return LyricsProviderResult(
        lines: lines,
        quality: quality,
        providerName: providerName,
        isInternet: isInternet,
      );
    } catch (_) {
      return null;
    }
  }

  /// Simpan ke disk cache dengan TTL 30 hari.
  Future<void> putDisk(
    String key,
    String rawLrc,
    LyricsProviderResult result,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'lrc': rawLrc,
        'quality': result.quality.toJson(),
        'provider': result.providerName,
        'isInternet': result.isInternet,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('$_prefixV2$key', jsonEncode(map));
    } catch (_) {}
  }

  // ── Failure TTL ───────────────────────────────────────────────────────────

  bool isRecentlyFailed(String key) {
    final at = _failedAtMs[key];
    if (at == null) return false;
    if (DateTime.now().millisecondsSinceEpoch - at > _failedTtlMs) {
      _failedAtMs.remove(key);
      return false;
    }
    return true;
  }

  void markFailed(String key) {
    _failedAtMs[key] = DateTime.now().millisecondsSinceEpoch;
  }

  // ── Invalidation ──────────────────────────────────────────────────────────

  void clearMemory() {
    _mem.clear();
    _failedAtMs.clear();
  }

  Future<void> clearAll() async {
    clearMemory();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefixV2)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

class _CacheEntry {
  final LyricsProviderResult result;
  final int cachedAtMs;
  _CacheEntry(this.result, this.cachedAtMs);
}
