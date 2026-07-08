import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaletteExtractor
//
// Thin async wrapper around palette_generator_plus.
// Extracts [dominant, vibrant, muted] colours from artwork bytes, caches the
// result by songId (LRU, 256 entries) so the extraction never runs twice for
// the same song.
//
// palette_generator_plus runs quantization in a background isolate by default
// (runInIsolate: true), so the UI thread is never blocked by decode/quantize.
// On web, where dart:isolate is unavailable, it transparently falls back to
// the main thread with an identical result.
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
  // decode + quantization pipeline, doubling processing time right when it
  // matters most.
  static final Map<int, Future<List<Color>>> _pending = {};

  // Artwork is downscaled before handing off to the quantizer. Native artwork
  // cache stores WebP up to 1000×1000 px, so without capping the decode size
  // here, extraction iterates millions of pixels per call. Quantization only
  // needs a coarse colour histogram, so a small decode target drastically cuts
  // processing time with no visible quality loss in the resulting palette.
  // 112 px is chosen as the sweet spot: large enough to retain colour regions
  // that matter, small enough to keep histogram buckets clean at 16 colours.
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
    try {
      // maximumColorCount = 16: sweet spot for a 112×112 px buffer.
      // More buckets on a histogram this small introduces noise from WebP
      // compression artefacts and edge-blur pixels rather than real colours.
      //
      // runInIsolate: true (explicit, matches the default) — keeps the entire
      // decode + quantization pipeline off the UI thread.
      final generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          MemoryImage(artwork),
          width: _quantizeTargetSize,
          height: _quantizeTargetSize,
        ),
        maximumColorCount: 24,
        // filters: [] — intentionally empty.
        // The default avoidRedBlackWhitePaletteFilter strips near-red,
        // near-black, and near-white colours from the candidate pool, which
        // makes sense for UI text-colour selection but hurts a generative
        // fluid shader: vivid reds, deep blacks, and bright whites are all
        // valid and desirable inputs for domain-warping colour blobs.
        // Removing the filter gives the shader the full colour space of the
        // artwork rather than a sanitised subset.
        filters: const [],
        runInIsolate: true,
      );

      final dominant = generator.dominantColor?.color ?? _kFallback[0];

      // Fallback chain: vibrant → lightVibrant → fallback.
      // lightVibrant preferred over darkVibrant as secondary because the
      // fluid shader (domain warping) needs high chroma/saturation input —
      // darkVibrant tends to be too dim to drive vivid colour blobs.
      final vibrant = generator.vibrantColor?.color
                   ?? generator.lightVibrantColor?.color
                   ?? _kFallback[1];

      // Fallback chain: muted → darkMuted → fallback.
      final muted = generator.mutedColor?.color
                 ?? generator.darkMutedColor?.color
                 ?? _kFallback[2];

      final colors = [dominant, vibrant, muted];
      _cache.put(songId, colors);
      return colors;
    } catch (_) {
      _cache.put(songId, _kFallback);
      return _kFallback;
    } finally {
      // Guaranteed cleanup regardless of success, exception, or any future
      // refactor that changes the catch clause — prevents songId from being
      // permanently stuck in _pending and blocking all future extractions.
      // ignore: unawaited_futures
      _pending.remove(songId); // Map.remove() returns the value — not awaited intentionally
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple LRU cache backed by a LinkedHashMap.
// ─────────────────────────────────────────────────────────────────────────────

class _LruCache<K, V> {
  _LruCache(this._maxSize);

  final int _maxSize;
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
