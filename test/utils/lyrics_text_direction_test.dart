import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/utils/lyrics_text_direction.dart';

void main() {
  group('LyricsTextDirection', () {
    test('uses LTR for Latin-only lyrics', () {
      expect(
        LyricsTextDirection.resolve('I love this song'),
        TextDirection.ltr,
      );
    });

    test('uses RTL when Arabic script is present', () {
      expect(LyricsTextDirection.resolve('أحب هذه الأغنية'), TextDirection.rtl);
    });

    test('uses RTL for Arabic lines containing embedded Latin text', () {
      expect(LyricsTextDirection.resolve('أحب this song'), TextDirection.rtl);
    });

    test('does not classify Arabic punctuation as a strong RTL signal', () {
      expect(LyricsTextDirection.resolve('hello، 123'), TextDirection.ltr);
    });
  });
}
