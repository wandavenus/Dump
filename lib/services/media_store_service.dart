import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/local_song.dart';
import 'log_service.dart';

class MediaStoreService {
  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const int _maxArtworkCacheEntries = 80;

  static final LinkedHashMap<int, Future<Uint8List?>> _artworkCache =
      LinkedHashMap<int, Future<Uint8List?>>();

  static List<LocalSong>? _songsCache;

  /// Synchronous read of the warm-up cache. Non-null after [warmUp] completes
  /// (i.e. from the very first [runApp] frame on a cold start). UI widgets can
  /// read this in [State.initState] to render without a loading spinner.
  static List<LocalSong>? get cachedSongs => _songsCache;

  // Whether a live MediaStore query has completed this process lifetime.
  // Starts false so the very first [getSongs] call after a cold start —
  // even one served instantly from the persisted list below — still kicks
  // off a background reconciliation with the real (possibly changed)
  // library.
  static bool _liveRefreshed = false;

  /// Dipancarkan setiap kali rescan selesai — value adalah event counter
  /// (increment +1 setiap rescan berhasil). Listener cukup panggil ulang
  /// load mereka tanpa peduli nilai aktualnya.
  static final ValueNotifier<int> rescanNotifier = ValueNotifier(0);

  // ── Disk persistence (stale-while-revalidate) ──────────────────────────────
  //
  // Enumerating MediaStore from scratch is the slowest step of a cold start —
  // every screen (home, list, player) waits on it before rendering anything,
  // which is what actually shows up to the user as a global ~0.5-1s "loading"
  // flash covering the whole UI, artwork included, right after the app is
  // killed and reopened (a live process, e.g. just minimized, never re-queries
  // and so never shows this).
  //
  // Fix: persist the last-fetched song list to disk. On the next cold start,
  // [warmUp] hydrates [_songsCache] from that file BEFORE runApp, so the very
  // first [getSongs] call returns instantly with the last-known library —
  // letting the whole UI (and each song's already-disk-cached artwork) paint
  // on the first frame. A real MediaStore query still runs right after, in
  // the background, to silently reconcile any actual library changes.
  static String? _cacheFilePath;

  static Future<String> _resolvedCacheFilePath() async {
    return _cacheFilePath ??=
        '${(await getApplicationCacheDirectory()).path}/song_list_cache.json';
  }

  /// Loads the persisted song list from disk into [_songsCache]. Call once
  /// during app startup (awaited, before `runApp`), alongside the artwork/
  /// palette warm-ups — this is what lets the very first frame render the
  /// full library (and its artwork) instead of a loading spinner.
  static Future<void> warmUp() async {
    if (kIsWeb) return;
    try {
      final path = await _resolvedCacheFilePath();
      final file = File(path);
      if (!file.existsSync()) return;

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _songsCache = decoded
          .map((m) => LocalSong.fromMap(Map<dynamic, dynamic>.from(m as Map)))
          .toList(growable: false);
    } catch (_) {
      // Corrupt or unreadable cache — fall through to a normal live query.
    }
  }

  static Future<void> _persist(List<LocalSong> songs) async {
    try {
      final path = await _resolvedCacheFilePath();
      final file = File(path);
      await file.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode(songs.map((s) => s.toMap()).toList()));
      await tmp.rename(path); // atomic — never leaves a half-written cache.
    } catch (_) {
      // Best-effort — a failed save just means next cold start falls back
      // to waiting on a live MediaStore query, same as today.
    }
  }

  // Deduplicates concurrent refreshes (startup reconcile racing a manual
  // pull-to-refresh, a rescan event, etc.) so only one MediaStore query runs
  // and every caller awaits the same in-flight result — mirrors the
  // in-flight dedup pattern already used by ArtworkRepository/PaletteExtractor.
  static Future<List<LocalSong>>? _inFlightRefresh;

  // Throttles reconcile retries after a failed background refresh so a
  // persistently-failing MediaStore query can't loop forever: getSongs() →
  // reconcile fails → listener re-reads getSongs() → reconcile again → ...
  static DateTime? _lastFailedReconcile;
  static const _reconcileRetryBackoff = Duration(seconds: 10);

  static Future<List<LocalSong>> getSongs() async {
    final cachedSongs = _songsCache;
    if (cachedSongs != null) {
      if (!_liveRefreshed) {
        final lastFailure = _lastFailedReconcile;
        if (lastFailure == null ||
            DateTime.now().difference(lastFailure) > _reconcileRetryBackoff) {
          // Serve the persisted/previous list immediately, and reconcile
          // with a real MediaStore query in the background — never blocks
          // this call or the first frame.
          unawaited(_reconcileInBackground());
        }
      }
      return cachedSongs;
    }

    return refreshSongs();
  }

  static Future<void> _reconcileInBackground() async {
    final before = _songsCache;
    final after = await refreshSongs();
    if (!_liveRefreshed) return; // refreshSongs() failed — do not notify.

    // Only nudge already-built lists to reload if the library actually
    // changed since the persisted snapshot — avoids a pointless rebuild on
    // every cold start when nothing changed since last session.
    if (!_sameSongs(before, after)) {
      rescanNotifier.value++;
    }
  }

  static bool _sameSongs(List<LocalSong>? a, List<LocalSong> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].path != b[i].path) return false;
    }
    return true;
  }

  static Future<List<LocalSong>> refreshSongs() {
    // Coalesce concurrent callers onto a single in-flight query/parse pass.
    final inFlight = _inFlightRefresh;
    if (inFlight != null) return inFlight;

    final future = _refreshSongsImpl();
    _inFlightRefresh = future;
    return future.whenComplete(() => _inFlightRefresh = null);
  }

  static Future<List<LocalSong>> _refreshSongsImpl() async {
    // MediaStore has no browser equivalent — `musicplayer/media_store` isn't
    // implemented on web. Serve a small in-memory sample library instead so
    // layout/UI (Home, Album/Artist detail, Search, Library) can be visually
    // checked in the web preview. Never used on Android — real device builds
    // always hit the native channel below.
    if (kIsWeb) {
      _songsCache = _webSampleSongs;
      _liveRefreshed = true;
      return _webSampleSongs;
    }

    try {
      final List<dynamic>? songs =
          await _channel.invokeListMethod('getSongs');

      final parsedSongs = (songs ?? const <dynamic>[])
          .map((song) =>
              LocalSong.fromMap(Map<dynamic, dynamic>.from(song)))
          .where((song) => song.path.isNotEmpty)
          .toList(growable: false);

      _songsCache = parsedSongs;
      _liveRefreshed = true;
      _lastFailedReconcile = null;
      unawaited(_persist(parsedSongs));
      return parsedSongs;
    } on PlatformException catch (error, stackTrace) {
      LogService.error('MediaStore', 'Failed to load songs: $error', stackTrace: stackTrace.toString());
      _lastFailedReconcile = DateTime.now();
      return const <LocalSong>[];
    } catch (error, stackTrace) {
      LogService.error('MediaStore', 'Invalid song payload: $error', stackTrace: stackTrace.toString());
      _lastFailedReconcile = DateTime.now();
      return const <LocalSong>[];
    }
  }

  // ── Web-only sample library (never used on Android) ───────────────────────
  static final List<LocalSong> _webSampleSongs = List.unmodifiable([
    const LocalSong(
      id: 1001, title: 'Senja di Ufuk', artist: 'Nadia Kirana',
      path: 'web-sample://1001', album: 'Cerita Kota', albumId: 5001,
      duration: Duration(minutes: 3, seconds: 42),
      year: 2022, trackNumber: 1, albumArtist: 'Nadia Kirana', genre: 'Pop',
    ),
    const LocalSong(
      id: 1002, title: 'Langkah Pertama', artist: 'Nadia Kirana',
      path: 'web-sample://1002', album: 'Cerita Kota', albumId: 5001,
      duration: Duration(minutes: 4, seconds: 5),
      year: 2022, trackNumber: 2, albumArtist: 'Nadia Kirana', genre: 'Pop',
    ),
    const LocalSong(
      id: 1003, title: 'Hujan November', artist: 'Nadia Kirana',
      path: 'web-sample://1003', album: 'Cerita Kota', albumId: 5001,
      duration: Duration(minutes: 3, seconds: 20),
      year: 2022, trackNumber: 3, albumArtist: 'Nadia Kirana', genre: 'Pop',
    ),
    const LocalSong(
      id: 1004, title: 'Jalan Pulang', artist: 'Bara Santoso',
      path: 'web-sample://1004', album: 'Perjalanan', albumId: 5002,
      duration: Duration(minutes: 5, seconds: 10),
      year: 2020, trackNumber: 1, albumArtist: 'Bara Santoso', genre: 'Rock',
    ),
    const LocalSong(
      id: 1005, title: 'Angin Malam', artist: 'Bara Santoso',
      path: 'web-sample://1005', album: 'Perjalanan', albumId: 5002,
      duration: Duration(minutes: 4, seconds: 30),
      year: 2020, trackNumber: 2, albumArtist: 'Bara Santoso', genre: 'Rock',
    ),
    const LocalSong(
      id: 1006, title: 'Rindu Sepanjang Jalan', artist: 'Bara Santoso',
      path: 'web-sample://1006', album: 'Perjalanan', albumId: 5002,
      duration: Duration(minutes: 3, seconds: 58),
      year: 2020, trackNumber: 3, albumArtist: 'Bara Santoso', genre: 'Rock',
    ),
    const LocalSong(
      id: 1007, title: 'Bintang Kecil Baru', artist: 'Diaz Ramadhan',
      path: 'web-sample://1007', album: 'Malam Kota', albumId: 5003,
      duration: Duration(minutes: 3, seconds: 15),
      year: 2023, trackNumber: 1, albumArtist: 'Diaz Ramadhan', genre: 'Jazz',
    ),
    const LocalSong(
      id: 1008, title: 'Kopi dan Kenangan', artist: 'Diaz Ramadhan',
      path: 'web-sample://1008', album: 'Malam Kota', albumId: 5003,
      duration: Duration(minutes: 4, seconds: 2),
      year: 2023, trackNumber: 2, albumArtist: 'Diaz Ramadhan', genre: 'Jazz',
    ),
    const LocalSong(
      id: 1009, title: 'Lampu Jalan', artist: 'Diaz Ramadhan',
      path: 'web-sample://1009', album: 'Malam Kota', albumId: 5003,
      duration: Duration(minutes: 3, seconds: 33),
      year: 2023, trackNumber: 3, albumArtist: 'Diaz Ramadhan', genre: 'Jazz',
    ),
    const LocalSong(
      id: 1010, title: 'Pelangi Setelah Hujan', artist: 'Nadia Kirana',
      path: 'web-sample://1010', album: 'Kilau', albumId: 5004,
      duration: Duration(minutes: 3, seconds: 48),
      year: 2024, trackNumber: 1, albumArtist: 'Nadia Kirana', genre: 'Pop',
    ),
    const LocalSong(
      id: 1011, title: 'Ombak Tenang', artist: 'Sinta Melati',
      path: 'web-sample://1011', album: 'Kilau', albumId: 5004,
      duration: Duration(minutes: 4, seconds: 12),
      year: 2024, trackNumber: 2, albumArtist: 'Sinta Melati', genre: 'Pop',
    ),
    const LocalSong(
      id: 1012, title: 'Cahaya Pertama', artist: 'Sinta Melati',
      path: 'web-sample://1012', album: 'Titik Awal', albumId: 5005,
      duration: Duration(minutes: 3, seconds: 27),
      year: 2021, trackNumber: 1, albumArtist: 'Sinta Melati', genre: 'Akustik',
    ),
  ]);

  static void clearSongsCache() {
    _songsCache = null;
  }

  /// Cancels the native background metadata pre-scanner.
  ///
  /// Call this when the user starts playback so the pre-scanner yields all
  /// I/O bandwidth to ExoPlayer's audio decode pipeline.
  /// Fire-and-forget — result is not awaited.
  static void cancelMetadataPrescanner() {
    _channel.invokeMethod<void>('cancelMetadataPrescanner').catchError((_) {});
  }

  /// Restarts the native background metadata pre-scanner.
  ///
  /// Call this when the playback queue ends (idle window) so songs played
  /// for the first time still get pre-cached for their next play.
  /// Uses the cached song list from the last [getSongs] call — no extra
  /// MediaStore round-trip.
  /// Fire-and-forget — result is not awaited.
  static void startMetadataPrescanner() {
    _channel.invokeMethod<void>('startMetadataPrescanner').catchError((_) {});
  }

  static Future<Uint8List?> getArtwork(int songId) {
    if (songId <= 0) return Future<Uint8List?>.value();

    final cachedArtwork = _artworkCache.remove(songId);
    if (cachedArtwork != null) {
      _artworkCache[songId] = cachedArtwork;
      return cachedArtwork;
    }

    final artworkFuture = _loadArtwork(songId);
    _artworkCache[songId] = artworkFuture;
    _trimArtworkCache();
    return artworkFuture;
  }

  static Future<Uint8List?> _loadArtwork(int songId) async {
    try {
      return _channel.invokeMethod<Uint8List>(
        'getArtwork',
        {'songId': songId},
      );
    } on PlatformException catch (error, stackTrace) {
      LogService.error('MediaStore', 'Failed to load artwork for song $songId: $error', stackTrace: stackTrace.toString());
      return null;
    } catch (error, stackTrace) {
      LogService.error('MediaStore', 'Invalid artwork payload for song $songId: $error', stackTrace: stackTrace.toString());
      return null;
    }
  }

  static void _trimArtworkCache() {
    while (_artworkCache.length > _maxArtworkCacheEntries) {
      _artworkCache.remove(_artworkCache.keys.first);
    }
  }

  static void clearArtworkCache() {
    _artworkCache.clear();
  }

  /// Menghapus lagu dari perangkat secara permanen.
  ///
  /// Pada Android 11+ akan menampilkan dialog konfirmasi sistem.
  /// Pada Android < 11 akan langsung menghapus via ContentResolver.
  /// Mengembalikan `true` jika berhasil dihapus.
  static Future<bool> deleteSong(int songId) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'deleteSong',
        {'songId': songId},
      );
      return result ?? false;
    } on PlatformException catch (error, stackTrace) {
      LogService.error('MediaStore', 'deleteSong platform error: $error', stackTrace: stackTrace.toString());
      return false;
    } catch (error, stackTrace) {
      LogService.error('MediaStore', 'deleteSong unexpected error: $error', stackTrace: stackTrace.toString());
      return false;
    }
  }

  // ── Artwork path (persistent cache) ────────────────────────────────────────

  /// Updates the native [ArtworkCacheManager] with the current playback queue.
  /// Songs in this set are never evicted during LRU cleanup.
  /// Call whenever the queue is set, shuffled, or items are added/removed.
  static Future<void> setActiveQueueIds(List<int> songIds) async {
    try {
      await _channel.invokeMethod<void>(
        'setActiveQueueIds',
        {'ids': songIds},
      );
    } catch (e) {
      LogService.error('MediaStore', 'setActiveQueueIds error: $e');
    }
  }

  static Future<String?> getArtworkPath(int songId) async {
    if (songId <= 0) return null;
    try {
      return await _channel.invokeMethod<String>(
        'getArtworkPath',
        {'songId': songId},
      );
    } on PlatformException catch (e) {
      LogService.error('MediaStore', 'getArtworkPath error songId=$songId: $e');
      return null;
    } catch (e) {
      LogService.error('MediaStore', 'getArtworkPath unexpected error songId=$songId: $e');
      return null;
    }
  }
}
