import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/lyrics_service/lrc_parser.dart';
import 'package:musicplayer/services/lyrics_service/quality.dart';

void main() {
  group('LrcParser', () {
    group('parseLrc', () {
      test('parses standard LRC timestamps correctly', () {
        const lrc = '[00:01.00]First line\n[00:05.50]Second line\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(2));
        expect(lines[0].timestamp, equals(const Duration(milliseconds: 1000)));
        expect(lines[0].text, equals('First line'));
        expect(lines[1].timestamp, equals(const Duration(milliseconds: 5500)));
        expect(lines[1].text, equals('Second line'));
      });

      test('parses timestamps without centiseconds [mm:ss]', () {
        const lrc = '[01:30]No centiseconds\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        expect(lines[0].timestamp, equals(const Duration(seconds: 90)));
        expect(lines[0].text, equals('No centiseconds'));
      });

      test('expands multi-timestamp lines', () {
        const lrc = '[00:10.00][00:20.00]Same text\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(2));
        expect(lines[0].timestamp, equals(const Duration(seconds: 10)));
        expect(lines[1].timestamp, equals(const Duration(seconds: 20)));
        expect(lines[0].text, equals('Same text'));
        expect(lines[1].text, equals('Same text'));
      });

      test('applies [offset:N] positive shift', () {
        const lrc = '[offset:500]\n[00:01.00]Shifted\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        expect(lines[0].timestamp, equals(const Duration(milliseconds: 1500)));
      });

      test('applies [offset:N] negative shift, clamps at zero', () {
        const lrc = '[offset:-2000]\n[00:01.00]Early\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        // 1000 - 2000 = -1000 → clamped to 0
        expect(lines[0].timestamp, equals(Duration.zero));
      });

      test('ignores metadata tags', () {
        const lrc = '[ti:My Song]\n[ar:Artist]\n[al:Album]\n[00:01.00]Lyric\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        expect(lines[0].text, equals('Lyric'));
      });

      test('strips inline Enhanced LRC word-timing tags', () {
        const lrc = '[00:01.00]<00:01.00>Hello <00:01.50>World\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        expect(lines[0].text, equals('Hello World'));
      });

      test('deduplicates consecutive identical timestamps', () {
        const lrc = '[00:05.00]Line A\n[00:05.00]Line A\n[00:10.00]Line B\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(2));
        expect(lines[0].timestamp, equals(const Duration(seconds: 5)));
        expect(lines[1].timestamp, equals(const Duration(seconds: 10)));
      });

      test('skips empty text lines', () {
        const lrc = '[00:01.00]\n[00:02.00]Real line\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines.length, equals(1));
        expect(lines[0].text, equals('Real line'));
      });

      test('returns empty list for empty input', () {
        final lines = LrcParser.parseLrc('');
        expect(lines, isEmpty);
      });

      test('sorts lines by timestamp ascending', () {
        const lrc = '[00:10.00]B\n[00:05.00]A\n[00:15.00]C\n';
        final lines = LrcParser.parseLrc(lrc);

        expect(lines[0].text, equals('A'));
        expect(lines[1].text, equals('B'));
        expect(lines[2].text, equals('C'));
      });
    });

    group('parse (auto-detect)', () {
      test('returns LyricsQuality.none for empty string', () {
        final result = LrcParser.parse('');
        expect(result.isEmpty, isTrue);
        expect(result.quality, equals(LyricsQuality.none));
      });

      test('detects lineTimedLrc for standard LRC', () {
        const lrc = '[00:01.00]Line one\n[00:05.00]Line two\n';
        final result = LrcParser.parse(lrc);

        expect(result.quality, equals(LyricsQuality.lineTimedLrc));
        expect(result.isNotEmpty, isTrue);
      });

      test('detects unsyncedLyrics for plain text', () {
        const plain = 'Line one\nLine two\nLine three\n';
        final result = LrcParser.parse(plain);

        expect(result.quality, equals(LyricsQuality.unsyncedLyrics));
        expect(result.lines.length, equals(3));
      });

      test('plain text timestamps are distributed across ~3m30s', () {
        final lines = List.generate(8, (i) => 'Line $i').join('\n');
        final result = LrcParser.parse(lines);

        expect(result.quality, equals(LyricsQuality.unsyncedLyrics));
        // First line always at t=0
        expect(result.lines.first.timestamp, equals(Duration.zero));
        // Timestamps should be monotonically increasing
        for (int i = 1; i < result.lines.length; i++) {
          expect(
            result.lines[i].timestamp > result.lines[i - 1].timestamp,
            isTrue,
          );
        }
      });

      test('detects wordTimedLrc for Enhanced LRC with many inline tags', () {
        // 2 lines, 4 inline tags → inlineCount(4) > lineCount(2)
        const enhanced =
            '[00:01.00]<00:01.00>Hello <00:01.50>World\n'
            '[00:05.00]<00:05.00>Foo <00:05.50>Bar\n';
        final result = LrcParser.parse(enhanced);

        expect(result.quality, equals(LyricsQuality.wordTimedLrc));
      });
    });

    group('detectQuality', () {
      test('returns none for empty string', () {
        expect(LrcParser.detectQuality(''), equals(LyricsQuality.none));
      });

      test('returns unsyncedLyrics for plain text', () {
        expect(
          LrcParser.detectQuality('Just plain text'),
          equals(LyricsQuality.unsyncedLyrics),
        );
      });

      test('returns lineTimedLrc for standard LRC', () {
        expect(
          LrcParser.detectQuality('[00:01.00]Line\n'),
          equals(LyricsQuality.lineTimedLrc),
        );
      });

      test('returns wordTimedLrc when inline tags outnumber lines', () {
        const lrc =
            '[00:01.00]<00:01.00>A <00:01.30>B\n'
            '[00:03.00]<00:03.00>C <00:03.30>D\n';
        expect(
          LrcParser.detectQuality(lrc),
          equals(LyricsQuality.wordTimedLrc),
        );
      });
    });
  });
}
