part of '../lyrics_service.dart';

/// Facade publik untuk sistem lirik.
///
/// API publik tidak berubah — semua halaman yang sudah ada tetap berjalan.
/// Implementasi sekarang didelegasikan ke [LyricsFetchManager] yang
/// menjalankan semua provider online SECARA PARALEL.
class LyricsService {
  // Catatan arsitektur: tidak ada cache di lapisan ini.
  // LyricsCacheManager (dikelola oleh LyricsFetchManager) adalah
  // satu-satunya sumber kebenaran untuk caching — memory + disk + failure TTL.
  // LyricsResult dibangun on-the-fly dari LyricsProviderResult; operasinya
  // sangat murah sehingga tidak perlu di-cache ulang di sini.

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

    // Sumber ditentukan dari flag typed — tidak ada string matching.
    final source = providerResult.isInternet
        ? LyricsSource.internet
        : providerResult.isEmbedded
        ? LyricsSource.embedded
        : LyricsSource.localFile;

    return LyricsResult(
      providerResult.lines,
      source,
      quality: providerResult.quality,
      providerName: providerResult.providerName,
      rawLrc: providerResult.rawLrc,
    );
  }

  /// Bersihkan cache (panggil ketika folder lirik berubah).
  static void clearCache() {
    LyricsFetchManager.instance.clearMemoryCache();
    LogService.verbose('LyricsService', 'Cache cleared');
  }

  /// Batalkan semua request yang sedang berjalan (mis. saat ganti lagu).
  static void cancelAll() => LyricsFetchManager.instance.cancelAll();

  // ── Parser (tetap publik untuk backward-compat) ───────────────────────────

  /// Parse LRC format ke daftar [LyricLine].
  /// Tetap publik karena digunakan oleh kode lain.
  static List<LyricLine> parseLrc(String lrc) => LrcParser.parseLrc(lrc);
}
