import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

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
  Color(0xFF2B313A),
  Color(0xFF4E657D),
  Color(0xFF7B8794),
];

  static final _cache = _LruCache<int, List<Color>>(256);

  // In-flight extraction dedup: without this, a concurrent prefetch call and
  // a UI-triggered call for the same songId (which happens routinely on a
  // track change — see AudioEngineManager prefetch racing animated_state's
  // own _loadPalette) would each independently run the full CPU-bound
  // decode + quantization pipeline, doubling UI-isolate blocking time right
  // when it matters most.
  static final Map<int, Future<List<Color>>> _pending = {};

  // Artwork is decoded and quantized synchronously on the UI isolate by the
  // palette_generator package (no internal downscaling, no isolate/compute
  // offload). Native artwork cache stores WebP up to 2000x2000px, so without
  // capping the decode size here, extraction can iterate millions of pixels
  // per call. Quantization only needs a coarse color histogram, so a small
  // decode target drastically cuts UI-isolate blocking time with no visible
  // quality loss in the resulting palette.
  static const int _quantizeTargetSize = 112;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the cached palette for [songId], or null if not yet extracted.
  static List<Color>? getSync(int songId) => _cache.get(songId);

  /// Extracts and caches the palette for [songId] from [artwork] bytes.
  /// Returns the cached result immediately if already available. Concurrent
  /// calls for the same [songId] share a single in-flight extraction.
  static Future<List<Color>> get(int songId, Uint8List artwork) {
    final cached = _cache.get(songId);
    if (cached != null) return Future.value(cached);

    final inFlight = _pending[songId];
    if (inFlight != null) return inFlight;

    final future = _extract(songId, artwork);
    _pending[songId] = future;
    return future;
  }

  static Future<List<Color>> _extract(int songId, Uint8List artwork) async {
    List<Color> colors;
    try {
      // maximumColorCount = 24 gives a good spread without excess computation.
      // ResizeImage caps the decoded pixel buffer so quantization runs over a
      // small, bounded number of pixels regardless of the source artwork's
      // native resolution.
      final generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          MemoryImage(artwork),
          width: _quantizeTargetSize,
          height: _quantizeTargetSize,
        ),
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
    // ignore: unawaited_futures
    _pending.remove(songId);
    return colors;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple LRU cache backed by a LinkedHashMap.
// ─────────────────────────────────────────────────────────────────────────────

class _LruCache<K, V> {
  _LruCache(this._maxSize);

  final int                _maxSize;
  final _map = <K, V>{};

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
