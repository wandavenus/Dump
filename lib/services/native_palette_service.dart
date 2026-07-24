import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // ignore: unnecessary_import — kept for Uint8List in public API signature

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativePaletteService
//
// Drop-in replacement for the old `PaletteExtractor` / `palette_generator_plus`
// pipeline.  Delegates color extraction to [NativePaletteBridge.kt] on the
// Android side, which uses Android's `androidx.palette:palette` library
// (MMCQ quantization) + a custom perceptual vibrancy-scoring and
// hue-diversity selection algorithm.
//
// Public API is identical to the old PaletteExtractor so callers need only
// change the class name:
//
//   getSync(songId)  → List<Color>?        synchronous LRU cache lookup
//   get(songId)      → Future<List<Color>> async extract + cache
//   warmUp()         → Future<void>        load persisted cache from disk
//   clearMemoryCache()                     free RAM; disk cache intact
//
// Cache behaviour is preserved verbatim:
//   • 256-entry LRU in memory
//   • Debounced disk persistence (palette_cache.json — same path/format)
//   • In-flight dedup: concurrent callers for the same songId share one Future
//   • On non-Android / web: returns the hardcoded fallback palette
// ─────────────────────────────────────────────────────────────────────────────

class NativePaletteService {
  NativePaletteService._();

  // Fallback palette when extraction fails or artwork is absent.
  // Identical to the old PaletteExtractor._kFallback so the persisted
  // palette_cache.json remains fully forward-compatible.
  static const List<Color> _kFallback = [
    Color(0xFF2B313A),
    Color(0xFF4E657D),
    Color(0xFF7B8794),
  ];

  static const _channel = MethodChannel('dev.wndavenz.music/native_palette');

  static final _cache = _LruCache<int, List<Color>>(256);

  // ── Disk persistence ────────────────────────────────────────────────────────
  // Same path / format as the old PaletteExtractor so existing cached palettes
  // survive the migration without any data loss.
  static String? _cacheFilePath;
  static bool _dirty = false;
  static Timer? _saveDebounce;

  /// Loads the persisted palette cache from disk.  Call once during app startup
  /// (awaited, before `runApp`) alongside `ArtworkRepository.warmUp` so
  /// `getSync` can serve previously-computed palettes on the very first frame.
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
        _cache.put(songId, values.map((v) => Color(v as int)).toList());
      }
    } catch (_) {
      // Corrupt or unreadable cache — start fresh, never crash startup.
    }
  }

  /// Debounced persistence: batches rapid extractions (prefetch waves) into a
  /// single disk write instead of one write per song.
  static void _schedulePersist() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  static Future<void> _persist() async {
    if (!_dirty) return;
    final path = _cacheFilePath;
    if (path == null) {
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
      // Atomic write: temp file → rename avoids a half-written cache.
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode(map));
      await tmp.rename(path);
    } catch (_) {
      // Best-effort — a failed save just means palettes recompute next launch.
    }
  }

  // In-flight dedup: concurrent callers for the same songId share one Future
  // instead of each independently running the full extraction pipeline.
  static final Map<int, Future<List<Color>>> _pending = {};

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns the cached palette for [songId], or null if not yet extracted.
  static List<Color>? getSync(int songId) => _cache.get(songId);

  /// Clears the in-memory LRU cache to free RAM.  Disk cache remains intact
  /// and will be re-hydrated on demand by [get].
  static void clearMemoryCache() => _cache.clear();

  /// Extracts and caches the palette for [songId].
  /// Returns the cached result immediately if already available.
  /// Concurrent calls for the same [songId] share a single in-flight future.
  ///
  /// The [artwork] parameter is accepted for API compatibility with old
  /// call sites but is intentionally ignored — the native bridge reads artwork
  /// directly from ArtworkCacheManager, so no bytes need to cross the channel.
  static Future<List<Color>> get(int songId, [Uint8List? artwork]) {
    final cached = _cache.get(songId);
    if (cached != null) return Future.value(cached);

    final inFlight = _pending[songId];
    if (inFlight != null) return inFlight;

    final future = _extract(songId);
    _pending[songId] = future;
    return future;
  }

  static Future<List<Color>> _extract(int songId) async {
    try {
      // Non-Android / web: return fallback immediately (no MethodChannel).
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return _kFallback;
      }

      final raw = await _channel.invokeListMethod<int>(
        'extractPalette',
        songId,
      );

      if (raw == null || raw.length < 3) {
        _cache.put(songId, _kFallback);
        return _kFallback;
      }

      final colors = raw.map(Color.new).toList(growable: false);
      _cache.put(songId, colors);
      _schedulePersist();
      return colors;
    } catch (_) {
      _cache.put(songId, _kFallback);
      return _kFallback;
    } finally {
      // ignore: unawaited_futures
      _pending.remove(songId); // Map.remove() returns the value — not awaited intentionally
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple LRU cache backed by a LinkedHashMap (identical to old implementation).
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
    if (_map.length > _maxSize) _map.remove(_map.keys.first);
  }

  void clear() => _map.clear();
}
