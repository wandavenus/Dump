part of '../synced_lyrics_view.dart';

/// Sebuah kata dengan timestamp-nya dari Enhanced LRC.
class ElrcWord {
  final String text;
  final Duration start;

  const ElrcWord(this.text, this.start);
}

/// Mengekstrak word timestamps per baris dari string Enhanced LRC mentah.
///
/// Ini adalah parser RENDERER — tidak memodifikasi [LrcParser].
/// Menghasilkan daftar yang PERSIS sama urutannya dengan [LrcParser.parseLrc],
/// sehingga `_elrcWordLines[i]` selalu sesuai dengan `lyrics[i]`.
class ElrcWordExtractor {
  static final _tsRe   = RegExp(r'\[(\d+):(\d+(?:[.,]\d+)?)\]');
  static final _inlineRe = RegExp(r'<(\d+):(\d+(?:[.,]\d+)?)>');
  static final _metaRe = RegExp(
    r'^\[(?:ti|ar|al|by|offset|length|re|ve|total|author|created)\s*:',
    caseSensitive: false,
  );

  /// Parse [rawLrc] dan kembalikan daftar kata per baris.
  ///
  /// Indeks dalam daftar ini TEPAT sama dengan indeks dalam daftar yang
  /// dihasilkan [LrcParser.parseLrc] pada string yang sama.
  ///
  /// Baris tanpa word timestamps menghasilkan daftar kosong.
  static List<List<ElrcWord>> extractAll(String rawLrc) {
    // Offset (ms) dari tag [offset:N]
    int offsetMs = 0;
    final offsetMatch = RegExp(
      r'^\[offset\s*:\s*([+-]?\d+)\]',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(rawLrc);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
    }

    // Kumpulkan (timestamp, wordList) sesuai urutan parse LrcParser.
    final entries = <(Duration, List<ElrcWord>)>[];

    for (final rawLine in rawLrc.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_metaRe.hasMatch(line)) continue;

      // Kumpulkan semua timestamp terdepan [mm:ss.xx]
      final timestamps = <Duration>[];
      int cursor = 0;
      for (final m in _tsRe.allMatches(line)) {
        if (m.start > cursor &&
            line.substring(cursor, m.start).trim().isNotEmpty) {
          break;
        }
        final min    = int.tryParse(m.group(1) ?? '') ?? 0;
        final secStr = (m.group(2) ?? '').replaceAll(',', '.');
        final sec    = double.tryParse(secStr) ?? 0.0;
        timestamps.add(
          Duration(milliseconds: ((min * 60 + sec) * 1000).round()),
        );
        cursor = m.end;
      }
      if (timestamps.isEmpty) continue;

      // Teks setelah semua timestamp terdepan
      final rest = line.substring(cursor);

      // Cek bahwa teks non-kosong setelah strip inline tags
      // (sama dengan kondisi skip di LrcParser)
      if (rest.replaceAll(_inlineRe, '').trim().isEmpty) continue;

      final words = _parseWords(rest, offsetMs);

      for (final ts in timestamps) {
        final adjusted = Duration(
          milliseconds: (ts.inMilliseconds + offsetMs).clamp(0, 9999999),
        );
        entries.add((adjusted, words));
      }
    }

    // Sort dan deduplikasi — sama persis dengan LrcParser
    entries.sort((a, b) => a.$1.compareTo(b.$1));

    if (entries.length > 1) {
      final deduped = <(Duration, List<ElrcWord>)>[entries.first];
      for (int i = 1; i < entries.length; i++) {
        if (entries[i].$1 != entries[i - 1].$1) {
          deduped.add(entries[i]);
        }
      }
      return deduped.map((e) => e.$2).toList();
    }
    return entries.map((e) => e.$2).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<ElrcWord> _parseWords(String rest, int offsetMs) {
    final matches = _inlineRe.allMatches(rest).toList();
    if (matches.isEmpty) return const [];

    final words = <ElrcWord>[];
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final min    = int.tryParse(m.group(1) ?? '') ?? 0;
      final secStr = (m.group(2) ?? '').replaceAll(',', '.');
      final sec    = double.tryParse(secStr) ?? 0.0;
      final startMs = ((min * 60 + sec) * 1000).round() + offsetMs;
      final wordStart = Duration(
        milliseconds: startMs.clamp(0, 9999999),
      );

      final textEnd   = i + 1 < matches.length ? matches[i + 1].start : rest.length;
      final wordText  = rest.substring(m.end, textEnd).trim();

      if (wordText.isNotEmpty) {
        words.add(ElrcWord(wordText, wordStart));
      }
    }
    return words;
  }
}
