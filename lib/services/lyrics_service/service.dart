part of '../lyrics_service.dart';

/// Facade publik untuk sistem lirik.
///
/// API publik tidak berubah — semua halaman yang sudah ada tetap berjalan.
/// Implementasi sekarang didelegasikan ke [LyricsFetchManager] yang
/// menjalankan semua provider online SECARA PARALEL.
class LyricsService {
  // Memory cache untuk backward-compat (juga ada di LyricsCacheManager)
  static final Map<String, LyricsResult> _cache = {};

  // ── Inisialisasi (dipanggil sekali dari main.dart / AudioEffectsService) ───

  static void init() {
    LyricsFetchManager.instance.setConfiguredFolderGetter(
      () => AudioEffectsService.lyricsPath.value,
    );
    LogService.verbose('LyricsService', 'Multi-provider system initialized');
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Ambil lirik: embedded → file lokal → memory cache → disk cache
  ///              → semua provider online (paralel).
  ///
  /// Parameter [filePath], [album], [durationMs] bersifat opsional tetapi
  /// meningkatkan akurasi pencarian dan cache.
  static Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    String? filePath,
    String? album,
    int? durationMs,
  }) async {
    // Cek legacy memory cache dulu (kompat dengan kode lama)
    final legacyKey = '$artist|$title|${filePath ?? ''}';
    if (_cache.containsKey(legacyKey)) {
      return _cache[legacyKey]!;
    }

    final query = LyricsQuery(
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      filePath: filePath,
    );

    final providerResult = await LyricsFetchManager.instance.fetch(query);

    if (providerResult == null || providerResult.isEmpty) {
      return const LyricsResult([], LyricsSource.none);
    }

    final source =
        providerResult.isInternet
            ? LyricsSource.internet
            : providerResult.providerName.contains('tag')
            ? LyricsSource.embedded
            : LyricsSource.localFile;

    final result = LyricsResult(
      providerResult.lines,
      source,
      quality: providerResult.quality,
      providerName: providerResult.providerName,
      rawLrc: providerResult.rawLrc,
    );

    _cache[legacyKey] = result;
    return result;
  }

  /// Bersihkan cache (panggil ketika folder lirik berubah).
  static void clearCache() {
    final count = _cache.length;
    _cache.clear();
    LyricsFetchManager.instance.clearMemoryCache();
    LogService.verbose('LyricsService', 'Cache cleared ($count entries)');
  }

  /// Batalkan semua request yang sedang berjalan (mis. saat ganti lagu).
  static void cancelAll() => LyricsFetchManager.instance.cancelAll();

  // ── Parser (tetap publik untuk backward-compat) ───────────────────────────

  /// Parse LRC format ke daftar [LyricLine].
  /// Tetap publik karena digunakan oleh kode lain.
  static List<LyricLine> parseLrc(String lrc) => LrcParser.parseLrc(lrc);
}
