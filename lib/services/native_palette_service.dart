import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // ignore: unnecessary_import — kept for Uint8List in public API signature

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativePaletteService
//
// Drop-in replacement for the old `PaletteExtractor` / `palette_generator_plus`
// pipeline.  Delegates color extraction to [NativePaletteBridge.kt] on the
// Android side, which uses Android's `androidx.palette:palette` library
// (MMCQ quantization) + population-led perceptual scoring, OKLab clustering,
// coverage/diversity role selection, and an extended 5-color output:
//
//   index 0 → primary   (main mood color)
//   index 1 → secondary (supporting color)
//   index 2 → accent    (strongest vibrant color)
//   index 3 → highlight (bright/highlight tone)
//   index 4 → shadow    (dark depth tone)
//
// Existing callers that only read indices [0], [1], [2] continue to work
// without any changes.
//
// Public API (unchanged):
//   getSync(songId)  → List<Color>?        synchronous LRU cache lookup
//   get(songId)      → Future<List<Color>> async extract + cache
//   warmUp()         → Future<void>        load persisted cache from disk
//   clearMemoryCache()                     free RAM; disk cache intact
//
// Cache behaviour:
//   • 256-entry LRU in memory
//   • Debounced disk persistence to palette_cache_v<native-version>.json
//   • Old 3-color entries are padded to 5 with fallback tones when loaded
//   • Persisted entries are validated before use; corrupt rows are skipped
//   • In-flight dedup: concurrent callers for the same songId share one Future
//   • invalidate(songId) drops memory rows and schedules disk removal when
//     artwork changes
//   • On non-Android / web: returns the hardcoded fallback palette
// ─────────────────────────────────────────────────────────────────────────────

class NativePaletteService {
  NativePaletteService._();

  /// 5-color fallback palette:
  ///   [0] primary, [1] secondary, [2] accent, [3] highlight, [4] shadow.
  /// First 3 entries are identical to the old 3-color fallback.
  static const List<Color> _kFallback = [
    Color(0xFF2B313A), // primary
    Color(0xFF4E657D), // secondary
    Color(0xFF7B8794), // accent
    Color(0xFFABBED4), // highlight
    Color(0xFF121821), // shadow
  ];

  static const _channel = MethodChannel('dev.wndavenz.music/native_palette');
  // Used only when the native channel is unavailable (web/non-Android or an
  // older engine). Android resolves the authoritative value from
  // NativePaletteBridge.getCacheVersion during warm-up.
  static const int _fallbackCacheVersion = 9;

  /// Upper bound for a single native extraction attempt. The native watchdog
  /// only starts after `Palette.generate` completes, so a stuck extraction
  /// would otherwise pin the caller (and the prefetch slot) forever.
  @visibleForTesting
  static Duration extractTimeout = const Duration(seconds: 8);

  /// Cache-version handshake is a tiny synchronous native getter, but a broken
  /// engine must not block startup indefinitely.
  static const Duration _cacheVersionTimeout = Duration(seconds: 2);

  static final _cache = _LruCache<int, List<Color>>(256);

  // ── Disk persistence ────────────────────────────────────────────────────────
  static String? _cacheFilePath;
  static bool _dirty = false;
  static bool _persisting = false;
  static Timer? _saveDebounce;

  /// Loads the persisted palette cache from disk.  Call once during app startup
  /// (awaited, before `runApp`) so `getSync` can serve previously-computed
  /// palettes on the very first frame.
  ///
  /// Handles both old 3-color entries (padded to 5 with fallback tones) and
  /// new 5-color entries transparently — no data loss or migration needed.
  static Future<void> warmUp() async {
    // The persisted cache uses path_provider and dart:io, neither of which
    // has a browser implementation. Web callers already use the in-memory
    // fallback/cache path, so skip disk warm-up instead of logging a plugin
    // exception during startup.
    if (kIsWeb) return;

    try {
      final dir = await getApplicationCacheDirectory();
      // The native algorithm version is authoritative on Android. It changes
      // the cache filename so a palette algorithm revision cannot reuse stale
      // persisted colors. Older/non-native engines use the compatibility value.
      var cacheVersion = _fallbackCacheVersion;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          cacheVersion =
              await _channel
                  .invokeMethod<int>('getCacheVersion')
                  .timeout(_cacheVersionTimeout) ??
              cacheVersion;
        } on TimeoutException catch (e, st) {
          LogService.debugPrintIfEnabled(
            '[NativePaletteService] native cache version timed out: '
            '$e\n$st',
          );
        } on PlatformException catch (e, st) {
          LogService.debugPrintIfEnabled(
            '[NativePaletteService] native cache version unavailable: '
            '$e\n$st',
          );
        } on MissingPluginException catch (e, st) {
          LogService.debugPrintIfEnabled(
            '[NativePaletteService] native cache version plugin unavailable: '
            '$e\n$st',
          );
        } on Object catch (e, st) {
          LogService.debugPrintIfEnabled(
            '[NativePaletteService] native cache version failed: '
            '$e\n$st',
          );
        }
      }
      _cacheFilePath = '${dir.path}/artwork/palette_cache_v$cacheVersion.json';
      final file = File(_cacheFilePath!);
      if (!file.existsSync()) return;

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        // A valid JSON array/string is still a corrupt cache. Drop it instead
        // of letting a TypeError escape this startup path.
        LogService.debugPrintIfEnabled(
          '[NativePaletteService] warmUp ignored non-object cache',
        );
        return;
      }
      for (final entry in decoded.entries) {
        final songId = int.tryParse(entry.key);
        final values = entry.value;
        // Accept both old (3-color) and new (5-color) formats in this cache
        // file. The versioned filename prevents entries from older algorithms
        // from being reused; 3-color entries in the current file are padded for
        // compatibility with older cache contents.
        if (songId == null || values is! List<Object?> || values.length < 3) {
          continue;
        }
        final colors = <Color>[];
        var malformed = false;
        for (final value in values) {
          // int.tryParse above already rejected non-string keys; JSON numbers
          // can still be out of the 32-bit ARGB range or non-integer.
          if (value is! int || value < 0 || value > 0xFFFFFFFF) {
            malformed = true;
            break;
          }
          colors.add(Color(value));
        }
        if (malformed) continue;
        final padded = _padToFive(colors);
        if (isHardFallback(padded)) continue;
        // Pad old 3-color entries to 5 so callers relying on indices 3/4
        // get something reasonable until the next real extraction.
        _cache.put(songId, padded);
      }
    } on Object catch (e, st) {
      // Corrupt or unreadable cache — start fresh, never crash startup.
      // Catch Object, not just Exception: a malformed persisted row used to
      // throw a TypeError (an Error, not an Exception) and skip runApp().
      LogService.debugPrintIfEnabled(
        '[NativePaletteService] warmUp failed: $e\n$st',
      );
    }
  }

  /// Returns exactly 5 colors: truncates longer rows and pads short rows with
  /// the fallback tones so every caller can rely on indices 0..4.
  static List<Color> _padToFive(List<Color> colors) {
    final result = colors.take(5).toList(growable: false);
    if (result.length == 5) return result;
    return [...result, for (int i = result.length; i < 5; i++) _kFallback[i]];
  }

  /// True when the native side had no usable artwork colours.
  static bool isHardFallback(List<Color> colors) {
    if (colors.length != _kFallback.length) return false;
    for (var i = 0; i < colors.length; i++) {
      if (colors[i].toARGB32() != _kFallback[i].toARGB32()) return false;
    }
    return true;
  }

  /// Debounced persistence: batches rapid extractions into a single disk write.
  static void _schedulePersist() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  static Future<void> _persist() async {
    // Serialize writes: overlapping calls used to share `$path.tmp`, so a
    // slow writer could rename a file that another writer had just truncated.
    if (_persisting) return;
    _persisting = true;
    try {
      while (_dirty) {
        final path = _cacheFilePath;
        if (path == null) {
          // D5 fix: nothing can be written without a cache path — clear the
          // dirty flag and stop instead of self-rescheduling forever. A later
          // extraction (after warmUp sets the path) calls _schedulePersist()
          // again, so no pending write is lost; the in-memory _cache keeps the
          // fresh results.
          _dirty = false;
          break;
        }
        _dirty = false;
        try {
          final map = <String, List<int>>{};
          for (final entry in _cache.entries) {
            map[entry.key.toString()] = entry.value
                .map((c) => c.toARGB32())
                .toList();
          }
          final file = File(path);
          await file.parent.create(recursive: true);
          // Atomic write: temp file → rename avoids a half-written cache.
          // Writes are serialized by _persisting, so this temp path has a
          // single writer.
          final tmp = File('$path.tmp');
          await tmp.writeAsString(jsonEncode(map));
          await tmp.rename(path);
        } on Exception catch (e, st) {
          // Best-effort — a failed save just means palettes recompute next
          // launch. IOException, FormatException, etc. all extend Exception.
          LogService.debugPrintIfEnabled(
            '[NativePaletteService] persist failed: $e\n$st',
          );
        }
      }
    } finally {
      _persisting = false;
    }
  }

  // In-flight dedup: concurrent callers for the same songId share one Future.
  static final Map<int, _PendingPalette> _pending = {};

  // Bumped by [invalidate]; an extraction started before the bump must not
  // write its (now stale) colors back into the cache.
  static final Map<int, int> _generations = {};

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns the cached palette for [songId], or null if not yet extracted.
  ///
  /// The returned list has 5 entries:
  ///   [0] primary, [1] secondary, [2] accent, [3] highlight, [4] shadow.
  static List<Color>? getSync(int songId) {
    final cached = _cache.get(songId);
    return cached != null && !isHardFallback(cached) ? cached : null;
  }

  /// Clears the in-memory LRU cache to free RAM.  Disk cache remains intact.
  static void clearMemoryCache() => _cache.clear();

  /// Drops every cached palette for [songId], including an extraction that is
  /// already in flight. Call this when the artwork bytes for a song change
  /// (cache eviction, re-download, or user edit) so a later request
  /// re-extracts instead of serving colors from the old image.
  static void invalidate(int songId) {
    _cache.remove(songId);
    _generations[songId] = _generationOf(songId) + 1;
    _pending.remove(songId);
    _schedulePersist();
  }

  /// Extracts and caches the palette for [songId].
  /// Returns the cached result immediately if already available.
  /// Concurrent calls for the same [songId] share a single in-flight future.
  ///
  /// The returned list has 5 entries:
  ///   [0] primary, [1] secondary, [2] accent, [3] highlight, [4] shadow.
  ///
  /// The [artwork] parameter is accepted for API compatibility with old
  /// call sites but is intentionally ignored — the native bridge reads artwork
  /// directly from ArtworkCacheManager.
  static Future<List<Color>> get(int songId, [Uint8List? artwork]) {
    final cached = _cache.get(songId);
    if (cached != null && !isHardFallback(cached)) {
      return Future.value(cached);
    }

    final generation = _generationOf(songId);
    final inFlight = _pending[songId];
    if (inFlight != null && inFlight.generation == generation) {
      return inFlight.future;
    }

    final future = _extract(songId, generation);
    final pending = _PendingPalette(generation, future);
    _pending[songId] = pending;
    // `.ignore()` both marks the secondary future as handled and keeps the
    // cleanup off the caller's result value.
    future.whenComplete(() {
      if (identical(_pending[songId], pending)) _pending.remove(songId);
    }).ignore();
    return future;
  }

  static int _generationOf(int songId) => _generations[songId] ?? 0;

  @visibleForTesting
  static void resetForTests() {
    _cache.clear();
    _pending.clear();
    _generations.clear();
    _dirty = false;
    _persisting = false;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _cacheFilePath = null;
    extractTimeout = const Duration(seconds: 8);
  }

  static Future<List<Color>> _extract(int songId, int generation) async {
    try {
      // Non-Android / web: no native extractor is available. Do not cache the
      // fallback, otherwise a later platform transition can never retry.
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return _kFallback;
      }

      // Artwork extraction can race the Media3 transition/cache prefetch.
      // Retry once so a transient null/error does not become visible as the
      // player's final background.
      for (var attempt = 0; attempt < 2; attempt++) {
        var retryDelay = const Duration(milliseconds: 120);
        try {
          final raw = await _channel
              .invokeListMethod<int>('extractPalette', songId)
              .timeout(extractTimeout);

          // Need at least 3 values; bridge normally returns 5. Validate each
          // int before constructing a Color: a buggy/older bridge response
          // must not throw an uncaught ArgumentError out of the cache layer.
          if (raw != null && raw.length >= 3) {
            final valid = raw.every((v) => v >= 0 && v <= 0xFFFFFFFF);
            if (valid) {
              final colors = _padToFive(
                raw.map(Color.new).toList(growable: false),
              );
              if (!isHardFallback(colors)) {
                if (generation != _generationOf(songId)) {
                  // The artwork was invalidated while this extraction was in
                  // flight. Returning fallback forces the caller to request the
                  // new artwork instead of displaying/caching stale colors.
                  return _kFallback;
                }
                _cache.put(songId, colors);
                _schedulePersist();
                return colors;
              }
            }
          }
        } on PlatformException catch (e, st) {
          if (e.code == 'palette_busy') {
            // Give the shared native artwork queue time to drain instead of
            // immediately adding another request to a saturated queue.
            retryDelay = const Duration(milliseconds: 240);
          }
          if (attempt == 1) {
            LogService.debugPrintIfEnabled(
              '[NativePaletteService] extraction failed for '
              'songId=$songId: $e\n$st',
            );
          }
        } on Exception catch (e, st) {
          // Includes TimeoutException from the Dart-side guard.
          if (attempt == 1) {
            LogService.debugPrintIfEnabled(
              '[NativePaletteService] extraction failed for '
              'songId=$songId: $e\n$st',
            );
          }
        }

        if (attempt == 0) {
          await Future<void>.delayed(retryDelay);
        }
      }

      // Do not cache fallback for a native/channel failure. Queue saturation,
      // a transient engine teardown, or a temporary decode failure must remain
      // retryable on the next call.
      return _kFallback;
    } on Object catch (e, st) {
      // Defensive boundary: an Error here (e.g. a future bridge regression)
      // should still degrade to the fallback instead of breaking the player.
      LogService.debugPrintIfEnabled(
        '[NativePaletteService] unexpected extraction error for '
        'songId=$songId: $e\n$st',
      );
      return _kFallback;
    }
  }
}

class _PendingPalette {
  const _PendingPalette(this.generation, this.future);

  final int generation;
  final Future<List<Color>> future;
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

  void remove(K key) => _map.remove(key);

  void clear() => _map.clear();
}
