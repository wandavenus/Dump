import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_song.dart';
import 'log_service.dart';

class MediaStoreService {
  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const int _maxArtworkCacheEntries = 80;

  static final LinkedHashMap<int, Future<Uint8List?>> _artworkCache =
      LinkedHashMap<int, Future<Uint8List?>>();

  static List<LocalSong>? _songsCache;

  /// Dipancarkan setiap kali rescan selesai — value adalah event counter
  /// (increment +1 setiap rescan berhasil). Listener cukup panggil ulang
  /// load mereka tanpa peduli nilai aktualnya.
  static final ValueNotifier<int> rescanNotifier = ValueNotifier(0);

  static Future<List<LocalSong>> getSongs() async {
    final cachedSongs = _songsCache;
    if (cachedSongs != null) {
      return cachedSongs;
    }

    return refreshSongs();
  }

  static Future<List<LocalSong>> refreshSongs() async {
    // MediaStore has no browser equivalent — `musicplayer/media_store` isn't
    // implemented on web. Serve a small in-memory sample library instead so
    // layout/UI (Home, Album/Artist detail, Search, Library) can be visually
    // checked in the web preview. Never used on Android — real device builds
    // always hit the native channel below.
    if (kIsWeb) {
      _songsCache = _webSampleSongs;
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
      return parsedSongs;
    } on PlatformException catch (error, stackTrace) {
      LogService.error('MediaStore', 'Failed to load songs: $error', stackTrace: stackTrace.toString());
      return const <LocalSong>[];
    } catch (error, stackTrace) {
      LogService.error('MediaStore', 'Invalid song payload: $error', stackTrace: stackTrace.toString());
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
