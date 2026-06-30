import '../../models/lyric_line.dart';
import 'quality.dart';

/// Hasil parse sebuah string lirik.
class ParsedLyrics {
  final List<LyricLine> lines;
  final LyricsQuality quality;

  const ParsedLyrics(this.lines, this.quality);

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

/// Parser LRC/Enhanced-LRC terpadu dengan deteksi kualitas otomatis.
///
/// Format yang didukung:
///   • Standard LRC      : `[mm:ss.xx]teks`
///   • No centiseconds   : `[mm:ss]teks`
///   • Multi-timestamp   : `[mm:ss.xx][mm:ss.xx]teks`
///   • Enhanced LRC      : `[mm:ss.xx]<mm:ss.xx>kata <mm:ss.xx>kata`
///   • Word-timed (A2)   : `[mm:ss.xx]<mm:ss.xx>word1<mm:ss.xx> <mm:ss.xx>word2`
///   • Metadata tags     : `[ti:]`, `[ar:]`, dsb → diabaikan
///   • `[offset:N]`      : diaplikasikan sebagai pergeseran timestamp (ms)
///   • Duplikat timestamp: dideduplikasi (entry pertama dipertahankan)
///   • Teks kosong       : dilewati
class LrcParser {
  // Regex untuk satu timestamp [mm:ss] atau [mm:ss.xx] atau [mm:ss.xxx]
  static final _tsRe = RegExp(r'\[(\d+):(\d+(?:[.,]\d+)?)\]');

  // Inline word-timing <mm:ss.xx>
  static final _inlineRe = RegExp(r'<\d+:\d+(?:[.,]\d+)?>');

  // Metadata: [ti:], [ar:], [al:], [offset:], dll.
  static final _metaRe = RegExp(
    r'^\[(?:ti|ar|al|by|offset|length|re|ve|total|author|created)\s*:',
    caseSensitive: false,
  );

  // Deteksi Enhanced LRC: ada ≥1 <mm:ss> inline di dalam baris
  static final _enhancedRe = RegExp(r'<\d+:\d+(?:[.,]\d+)?>', multiLine: true);

  // ─────────────────────────────────────────────────────────────────────────

  /// Parse string lirik — otomatis deteksi LRC vs plain-text.
  static ParsedLyrics parse(String raw) {
    if (raw.trim().isEmpty) return const ParsedLyrics([], LyricsQuality.none);

    // Deteksi format
    final hasTimestamps = RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(raw);
    if (!hasTimestamps) {
      return _parsePlain(raw);
    }

    // Hitung inline word-timing tags untuk menentukan LyricsQuality
    final inlineMatches = _enhancedRe.allMatches(raw).length;
    final lineCount = raw.split('\n').where((l) => l.trim().isNotEmpty).length;

    // Jika rata-rata > 1 tag inline per baris → word-timed Enhanced LRC
    final quality = inlineMatches > lineCount
        ? LyricsQuality.wordTimedLrc
        : inlineMatches > 0
            ? LyricsQuality.charTimedLrc
            : LyricsQuality.lineTimedLrc;

    final lines = parseLrc(raw);
    if (lines.isEmpty) return const ParsedLyrics([], LyricsQuality.none);
    return ParsedLyrics(lines, quality);
  }

  /// Parse plain text (tanpa timestamp) — distribusikan secara proporsional
  /// across ~3 menit 30 detik agar auto-scroll tetap bermakna.
  static ParsedLyrics _parsePlain(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const ParsedLyrics([], LyricsQuality.none);
    final int stepMs = lines.length > 1
        ? (210000 / (lines.length - 1)).round().clamp(1000, 4000)
        : 0;
    final result = List.generate(
      lines.length,
      (i) => LyricLine(
        timestamp: Duration(milliseconds: i * stepMs),
        text: lines[i],
      ),
    );
    return ParsedLyrics(result, LyricsQuality.unsyncedLyrics);
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Parse LRC format ke daftar [LyricLine].
  ///
  /// Sama seperti parser lama di LyricsService (dipertahankan untuk
  /// backward-compat dengan kode yang memanggil LyricsService.parseLrc).
  static List<LyricLine> parseLrc(String lrc) {
    // Ekstrak [offset:N]
    int offsetMs = 0;
    final offsetRe = RegExp(
      r'^\[offset\s*:\s*([+-]?\d+)\]',
      caseSensitive: false,
      multiLine: true,
    );
    final offsetMatch = offsetRe.firstMatch(lrc);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
    }

    final result = <LyricLine>[];

    for (final rawLine in lrc.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_metaRe.hasMatch(line)) continue;

      // Kumpulkan semua timestamp terdepan
      final List<Duration> timestamps = [];
      int cursor = 0;
      for (final m in _tsRe.allMatches(line)) {
        if (m.start > cursor &&
            line.substring(cursor, m.start).trim().isNotEmpty) {
          break;
        }
        final min = int.tryParse(m.group(1) ?? '') ?? 0;
        final secStr = (m.group(2) ?? '').replaceAll(',', '.');
        final sec = double.tryParse(secStr) ?? 0;
        timestamps.add(
          Duration(milliseconds: ((min * 60 + sec) * 1000).round()),
        );
        cursor = m.end;
      }

      if (timestamps.isEmpty) continue;

      // Teks = sesudah timestamp terakhir, strip inline word-timing
      final rawText =
          line.substring(cursor).replaceAll(_inlineRe, '').trim();
      if (rawText.isEmpty) continue;

      for (final ts in timestamps) {
        final adjusted = Duration(
          milliseconds: (ts.inMilliseconds + offsetMs).clamp(0, 9999999),
        );
        result.add(LyricLine(timestamp: adjusted, text: rawText));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Deduplikasi timestamp konsekutif identik
    if (result.length > 1) {
      final deduped = <LyricLine>[result.first];
      for (int i = 1; i < result.length; i++) {
        if (result[i].timestamp != result[i - 1].timestamp) {
          deduped.add(result[i]);
        }
      }
      return deduped;
    }
    return result;
  }

  /// Deteksi kualitas dari string LRC tanpa full parse.
  static LyricsQuality detectQuality(String raw) {
    if (raw.trim().isEmpty) return LyricsQuality.none;
    final hasTs = RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(raw);
    if (!hasTs) return LyricsQuality.unsyncedLyrics;

    final inlineCount = _enhancedRe.allMatches(raw).length;
    final lineCount =
        raw.split('\n').where((l) => l.trim().isNotEmpty).length.clamp(1, 9999);
    if (inlineCount > lineCount) return LyricsQuality.wordTimedLrc;
    if (inlineCount > 0) return LyricsQuality.charTimedLrc;
    return LyricsQuality.lineTimedLrc;
  }
}
