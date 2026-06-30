// ignore_for_file: unawaited_futures

import 'dart:async';

import '../../models/lyric_line.dart';
import '../../services/log_service.dart';
import 'cache_manager.dart';
import 'cancellation.dart';
import 'provider.dart';
import 'quality.dart';
import 'rate_limiter.dart';
import 'providers/embedded_provider.dart';
import 'providers/kugou_provider.dart';
import 'providers/kuwo_provider.dart';
import 'providers/local_file_provider.dart';
import 'providers/lrclib_provider.dart';
import 'providers/musixmatch_provider.dart';
import 'providers/netease_provider.dart';
import 'providers/qq_music_provider.dart';

/// Timeout dan window settings
const _globalDeadline  = Duration(seconds: 15);
const _upgradeWindow   = Duration(seconds: 2);

/// Orkestrasi pengambilan lirik dari semua provider.
///
/// Urutan:
///   1. Memory cache
///   2. Disk cache
///   3. Local providers (embedded tag → file lokal)   — sequential, cepat
///   4. Online providers                              — PARALEL
///
/// Prioritas kualitas: wordTimedLrc > charTimedLrc > lineTimedLrc > plainLrc > unsyncedLyrics
class LyricsFetchManager {
  static final LyricsFetchManager instance = LyricsFetchManager._();
  LyricsFetchManager._();

  // Token aktif — dibatalkan ketika lagu berganti
  CancellationToken? _activeToken;

  // ── Provider registry ──────────────────────────────────────────────────────

  final List<LyricsProvider> _localProviders = [
    EmbeddedProvider(),
    const LocalFileProvider(
      getConfiguredFolder: _getConfiguredFolder,
    ),
  ];

  final List<LyricsProvider> _onlineProviders = [
    LrclibProvider(),
    NeteaseProvider(),
    KugouProvider(),
    KuwoProvider(),
    QQMusicProvider(),
    const MusixmatchProvider(), // requires userToken — graceful skip if absent
  ];

  static String Function() _configuredFolderGetter = () => '';

  static String _getConfiguredFolder() => _configuredFolderGetter();

  /// Daftarkan getter folder lirik (dipanggil dari AudioEffectsService).
  void setConfiguredFolderGetter(String Function() getter) {
    _configuredFolderGetter = getter;
  }

  /// Tambah provider baru secara runtime (mis. Spotify jika token tersedia).
  void registerOnlineProvider(LyricsProvider provider) {
    if (!_onlineProviders.any((p) => p.name == provider.name)) {
      _onlineProviders.add(provider);
    }
  }

  // ── Main fetch entry point ─────────────────────────────────────────────────

  /// Ambil lirik dengan full pipeline.
  /// Membatalkan request sebelumnya secara otomatis.
  Future<LyricsProviderResult?> fetch(LyricsQuery query) async {
    // Batalkan request lagu sebelumnya
    _activeToken?.cancel();
    final token = CancellationToken();
    _activeToken = token;

    final key = query.cacheKey;
    final sw  = Stopwatch()..start();

    // 1. Memory cache
    final memResult = LyricsCacheManager.instance.getMemory(key);
    if (memResult != null) {
      LogService.verbose('FetchManager',
          'Memory cache hit: "${query.title}" [${memResult.quality.displayName}]');
      return memResult;
    }

    // 2. Failure TTL — jangan coba lagi jika baru-baru ini gagal total
    if (LyricsCacheManager.instance.isRecentlyFailed(key)) {
      LogService.verbose('FetchManager',
          'Failure TTL active: "${query.title}" — skip');
      return null;
    }

    LogService.log('FetchManager', 'Fetching: "${query.title}" — ${query.artist}');

    // 3. Disk cache
    if (!token.isCancelled) {
      final diskResult = await LyricsCacheManager.instance.getDisk(key);
      if (diskResult != null) {
        LyricsCacheManager.instance.putMemory(key, diskResult);
        LogService.verbose('FetchManager',
            'Disk cache hit: "${query.title}" [${diskResult.quality.displayName}]');
        return diskResult;
      }
    }

    // 4. Local providers (sequential — embedded tag → file lokal)
    for (final provider in _localProviders) {
      if (token.isCancelled) return null;
      try {
        final result = await provider.fetch(query, token);
        if (result != null && result.isNotEmpty) {
          LogService.log('FetchManager',
              '${provider.name}: "${query.title}" — ${result.lines.length} lines'
              ' [${result.quality.displayName}] (${sw.elapsedMilliseconds}ms)');
          LyricsCacheManager.instance.putMemory(key, result);
          // Local results tidak disimpan ke disk cache (sudah ada di disk)
          return result;
        }
      } catch (e) {
        if (e is CancelledException) return null;
        LogService.verbose('FetchManager', '${provider.name} error: $e');
      }
    }

    // 5. Online providers — SEMUA BERJALAN PARALEL
    if (token.isCancelled) return null;
    LogService.verbose('FetchManager',
        'Starting ${_onlineProviders.length} online providers in parallel');

    final onlineResult = await _runParallel(_onlineProviders, query, token);

    if (token.isCancelled) return null;

    if (onlineResult != null && onlineResult.isNotEmpty) {
      LogService.log('FetchManager',
          'Online result: "${query.title}" — ${onlineResult.lines.length} lines'
          ' [${onlineResult.quality.displayName}]'
          ' from ${onlineResult.providerName}'
          ' (${sw.elapsedMilliseconds}ms)');

      LyricsCacheManager.instance.putMemory(key, onlineResult);

      // Simpan ke disk cache — cari string LRC untuk disimpan
      unawaited(_saveToDisk(key, onlineResult));

      return onlineResult;
    }

    // 6. Tidak ditemukan — catat failure TTL
    LyricsCacheManager.instance.markFailed(key);
    LogService.warn('FetchManager',
        'Not found: "${query.title}" — ${query.artist} (${sw.elapsedMilliseconds}ms)');
    return null;
  }

  // ── Parallel online execution ──────────────────────────────────────────────

  Future<LyricsProviderResult?> _runParallel(
    List<LyricsProvider> providers,
    LyricsQuery query,
    CancellationToken token,
  ) async {
    if (providers.isEmpty) return null;

    // Filter provider yang sedang rate-limited
    final active = providers
        .where((p) => !ProviderRateLimiter.instance.isLimited(p.name))
        .toList();
    if (active.isEmpty) return null;

    LyricsProviderResult? best;
    LyricsQuality bestQuality = LyricsQuality.none;
    int remaining = active.length;

    final allDoneCompleter = Completer<void>();
    Timer? upgradeTimer;
    final upgradeCompleter = Completer<void>();

    void onProviderResult(LyricsProviderResult? result) {
      remaining--;
      if (token.isCancelled) {
        if (remaining == 0 && !allDoneCompleter.isCompleted) {
          allDoneCompleter.complete();
        }
        return;
      }

      if (result != null && result.isNotEmpty) {
        final isUpgrade = best == null || result.quality.isBetterThan(bestQuality);
        if (isUpgrade) {
          best = result;
          bestQuality = result.quality;
          LogService.verbose('FetchManager',
              '${result.providerName}: [${result.quality.displayName}] ($remaining remaining)');

          // Jika kualitas maksimal (word-timed), selesaikan segera
          if (bestQuality == LyricsQuality.wordTimedLrc) {
            upgradeTimer?.cancel();
            if (!upgradeCompleter.isCompleted) upgradeCompleter.complete();
            return;
          }

          // Mulai / reset upgrade window
          upgradeTimer?.cancel();
          upgradeTimer = Timer(_upgradeWindow, () {
            if (!upgradeCompleter.isCompleted) upgradeCompleter.complete();
          });
        }
      }

      if (remaining == 0 && !allDoneCompleter.isCompleted) {
        allDoneCompleter.complete();
      }
    }

    // Jalankan semua provider secara paralel
    for (final provider in active) {
      provider.fetch(query, token).then(onProviderResult).catchError((e) {
        if (e is! CancelledException) {
          LogService.verbose('FetchManager', '${provider.name} error: $e');
        }
        onProviderResult(null);
      });
    }

    // Tunggu: semua selesai, upgrade window, atau global deadline
    await Future.any([
      allDoneCompleter.future,
      upgradeCompleter.future,
      Future.delayed(_globalDeadline),
    ]);

    upgradeTimer?.cancel();
    return best;
  }

  // ── Disk cache write ───────────────────────────────────────────────────────

  Future<void> _saveToDisk(String key, LyricsProviderResult result) async {
    // Gunakan rawLrc asli jika tersedia (mempertahankan word timestamps ELRC).
    // Jika tidak ada, rekonstruksi LRC standar dari lines.
    final String lrcToSave = result.rawLrc ?? _reconstructLrc(result.lines);
    await LyricsCacheManager.instance.putDisk(key, lrcToSave, result);
  }

  String _reconstructLrc(List<LyricLine> lines) {
    final buf = StringBuffer();
    for (final line in lines) {
      final ms  = line.timestamp.inMilliseconds;
      final min = ms ~/ 60000;
      final sec = ((ms % 60000) / 1000.0);
      final secStr = sec.toStringAsFixed(2).padLeft(5, '0');
      buf.writeln('[${min.toString().padLeft(2, '0')}:$secStr]${line.text}');
    }
    return buf.toString();
  }

  // ── Cache management ───────────────────────────────────────────────────────

  void clearMemoryCache() => LyricsCacheManager.instance.clearMemory();

  Future<void> clearAllCache() => LyricsCacheManager.instance.clearAll();

  /// Batalkan semua request yang sedang berjalan (mis. saat app di-background).
  void cancelAll() {
    _activeToken?.cancel();
    _activeToken = null;
  }
}

void unawaited(Future<void> future) {
  // Intentionally not awaited
}
