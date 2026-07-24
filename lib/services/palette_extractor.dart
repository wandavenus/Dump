import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  // ── Disk persistence ────────────────────────────────────────────────────────
  //
  // Palettes are cheap to store (3 ARGB ints per song) but expensive to
  // recompute (decode + quantize). Without persisting them, every palette
  // that backs a visible background colour/shader (album cards, player
  // background) is lost on app kill and must be recomputed from scratch on
  // the next cold start — causing a visible flash from the fallback colour
  // to the real one, even though the underlying artwork image itself renders
  // instantly via ArtworkRepository's own disk cache. Persisting mirrors
  // that same "instant on cold start" behaviour for colours.
  static String? _cacheFilePath;
  static bool _dirty = false;
  static Timer? _saveDebounce;

  /// Loads the persisted palette cache from disk. Call once during app
  /// startup (awaited, before `runApp`), alongside `ArtworkRepository.warmUp`,
  /// so `getSync` can serve previously-computed palettes on the very first
  /// frame after the app is killed/reopened.
  static Future<void> warmUp() async {
    try {
      final dir = await getApplicationCacheDirectory();
      _cacheFilePath = '${dir.path}/artwork/palette_cache.json';
      final file = File(_cacheFilePath!);
      if (!file.existsSync()) return;

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final songId = int.tryParse(entry.key);
        final values = entry.value;
        if (songId == null || values is! List || values.length != 3) continue;
        final colors = values.map((v) => Color(v as int)).toList();
        _cache.put(songId, colors);
      }
    } catch (_) {
      // Corrupt or unreadable cache file — start fresh, never crash startup.
    }
  }

  /// Debounced persistence: batches rapid-fire extractions (e.g. prefetching
  /// an entire album grid) into a single disk write instead of one per song.
  static void _schedulePersist() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  static Future<void> _persist() async {
    if (!_dirty) return;
    final path = _cacheFilePath;
    if (path == null) {
      // warmUp() hasn't resolved yet (or failed) — keep _dirty set and retry
      // shortly instead of silently dropping the pending write.
      _saveDebounce = Timer(const Duration(milliseconds: 800), _persist);
      return;
    }
    _dirty = false;

    try {
      final map = <String, List<int>>{};
      for (final entry in _cache.entries) {
        map[entry.key.toString()] =
            entry.value.map((c) => c.toARGB32()).toList();
      }
      final file = File(path);
      await file.parent.create(recursive: true);
      // Write to a temp file then rename — atomic, avoids a half-written
      // cache file if the app is killed mid-write.
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode(map));
      await tmp.rename(path);
    } catch (_) {
      // Best-effort — a failed save just means palettes recompute next launch.
    }
  }

  // In-flight extraction dedup: without this, a concurrent prefetch call and
  // a UI-triggered call for the same songId (which happens routinely on a
  // track change — see PlaybackManager prefetch racing animated_state's
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

  /// Clears the in-memory palette cache to free up RAM. Disk cache remains
  /// intact and will be re-hydrated on demand.
  static void clearMemoryCache() => _cache.clear();

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

      final swatches = generator.paletteColors.where((swatch) {
  final hsl = HSLColor.fromColor(swatch.color);

  // Buang warna hampir hitam/putih/abu.
  return hsl.saturation >= 0.20 &&
         hsl.lightness >= 0.12 &&
         hsl.lightness <= 0.90;
}).toList();

if (swatches.length >= 3) {
  final colors = [
    swatches[0].color,
    swatches[1].color,
    swatches[2].color,
  ];

  _cache.put(songId, colors);
  _schedulePersist();
  return colors;
}

// Fallback kalau hasil filter kurang dari 3 warna.
final dominant = generator.dominantColor?.color ?? _kFallback[0];

final vibrant =
    generator.vibrantColor?.color ??
    generator.lightVibrantColor?.color ??
    _kFallback[1];

final muted =
    generator.mutedColor?.color ??
    generator.darkMutedColor?.color ??
    _kFallback[2];

final colors = [dominant, vibrant, muted];

_cache.put(songId, colors);
_schedulePersist();
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

  Iterable<MapEntry<K, V>> get entries => _map.entries;

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > _maxSize) {
      _map.remove(_map.keys.first); // evict least-recently-used
    }
  }

  void clear() => _map.clear();
}
