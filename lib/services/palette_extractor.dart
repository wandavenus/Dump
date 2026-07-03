import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaletteExtractor
//
// Thin async wrapper around palette_generator.
// Extracts [dominant, vibrant, muted] colours from artwork bytes, caches the
// result by songId (LRU, 64 entries) so the extraction never runs twice for
// the same song.
//
// Public API
//   getSync(songId)         → List<Color>?        synchronous cache lookup
//   get(songId, artwork)    → Future<List<Color>>  async extract + cache
// ─────────────────────────────────────────────────────────────────────────────

class PaletteExtractor {
  PaletteExtractor._();

  // Fallback palette when artwork is absent or extraction fails.
  static const List<Color> _kFallback = [
    Color(0xFF1A2A4A), // dominant  — deep navy
    Color(0xFF2E5090), // vibrant   — mid blue
    Color(0xFF4A6080), // muted     — steel blue
  ];

  static final _cache = _LruCache<int, List<Color>>(64);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the cached palette for [songId], or null if not yet extracted.
  static List<Color>? getSync(int songId) => _cache.get(songId);

  /// Extracts and caches the palette for [songId] from [artwork] bytes.
  /// Returns the cached result immediately if already available.
  static Future<List<Color>> get(int songId, Uint8List artwork) async {
    final cached = _cache.get(songId);
    if (cached != null) return cached;

    List<Color> colors;
    try {
      // palette_generator handles downscaling internally.
      // maximumColorCount = 16 gives a good spread without excess computation.
      final generator = await PaletteGenerator.fromImageProvider(
        MemoryImage(artwork),
        maximumColorCount: 16,
      );

      final dominant = generator.dominantColor?.color ?? _kFallback[0];
      final vibrant  = generator.vibrantColor?.color  ?? _kFallback[1];
      final muted    = generator.mutedColor?.color    ?? _kFallback[2];

      colors = [dominant, vibrant, muted];
    } catch (_) {
      colors = _kFallback;
    }

    _cache.put(songId, colors);
    return colors;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple LRU cache backed by a LinkedHashMap.
// ─────────────────────────────────────────────────────────────────────────────

class _LruCache<K, V> {
  _LruCache(this._maxSize);

  final int                _maxSize;
  final _map = LinkedHashMap<K, V>();

  V? get(K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value; // re-insert as most-recently-used
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > _maxSize) {
      _map.remove(_map.keys.first); // evict least-recently-used
    }
  }
}
