import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/widgets/player/synced_lyrics_view/karaoke_layout_cache.dart';

void main() {
  late KaraokeLayoutCache cache;

  setUp(() {
    cache = KaraokeLayoutCache(maxEntries: 2);
  });

  tearDown(() {
    cache.dispose();
  });

  KaraokeLineLayout prepare({
    required int index,
    double width = 280,
    double fontSize = 28,
  }) {
    return cache.obtain(
      lineIndex: index,
      text: 'hello world',
      wordTexts: const ['hello', 'world'],
      maxWidth: width,
      fontSize: fontSize,
      textScaleFactor: 1,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      activeColor: Colors.white,
      dimColor: Colors.white54,
    );
  }

  test('reuses a prepared layout for an unchanged line configuration', () {
    final first = prepare(index: 0);
    final second = prepare(index: 0);

    expect(identical(second, first), isTrue);
    expect(first.wordBoxes, hasLength(2));
    expect(first.wordBoxes.every((boxes) => boxes.isNotEmpty), isTrue);
  });

  test('rebuilds a line layout when its measured width changes', () {
    final first = prepare(index: 0);
    final second = prepare(index: 0, width: 240);

    expect(identical(second, first), isFalse);
  });

  test('keeps the cache bounded and evicts the least recently used line', () {
    final first = prepare(index: 0);
    final second = prepare(index: 1);

    // Touch line 0 so line 1 becomes the least-recently-used entry.
    expect(identical(prepare(index: 0), first), isTrue);
    prepare(index: 2);

    expect(identical(prepare(index: 0), first), isTrue);
    expect(identical(prepare(index: 1), second), isFalse);
  });

  test('rejects layout requests after disposal', () {
    cache.dispose();

    expect(() => prepare(index: 0), throwsStateError);
  });
}
