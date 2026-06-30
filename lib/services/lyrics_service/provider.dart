import '../../models/lyric_line.dart';
import 'cancellation.dart';
import 'quality.dart';

/// Hasil mentah dari satu provider lirik.
/// Dikonversi ke [LyricsResult] oleh [LyricsFetchManager].
class LyricsProviderResult {
  final List<LyricLine> lines;
  final LyricsQuality quality;
  final String providerName;
  final bool isInternet;

  const LyricsProviderResult({
    required this.lines,
    required this.quality,
    required this.providerName,
    this.isInternet = false,
  });

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

/// Parameter pencarian lirik yang dikirim ke semua provider.
class LyricsQuery {
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? filePath;

  const LyricsQuery({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.filePath,
  });

  String get cacheKey {
    final a = artist.toLowerCase().trim();
    final t = title.toLowerCase().trim();
    final al = (album ?? '').toLowerCase().trim();
    final d = durationMs ?? 0;
    return '$a|$t|$al|$d';
  }

  /// Key sederhana tanpa album/durasi — untuk lookup cache lama.
  String get legacyKey => '$artist|$title|${filePath ?? ''}';
}

/// Abstract class yang harus diimplementasikan oleh setiap provider lirik.
abstract class LyricsProvider {
  /// Nama provider yang ditampilkan ke pengguna (mis. "LRCLIB", "NetEase").
  String get name;

  /// True jika provider ini memerlukan jaringan internet.
  bool get isOnline;

  /// Ambil lirik. Return null jika tidak ditemukan / error.
  /// Periksa [cancelToken.isCancelled] secara berkala.
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  );
}
