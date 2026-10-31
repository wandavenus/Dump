import 'dart:collection';

import 'package:flutter/material.dart';

/// Text geometry for one karaoke line. The cache owns both painters and
/// disposes them when the entry is evicted or invalidated.
class KaraokeLineLayout {
  final TextPainter basePainter;
  final TextPainter highlightPainter;
  final List<List<KaraokeWordBox>> wordBoxes;

  const KaraokeLineLayout({
    required this.basePainter,
    required this.highlightPainter,
    required this.wordBoxes,
  });

  void dispose() {
    basePainter.dispose();
    highlightPainter.dispose();
  }
}

/// A visual box belonging to one timed word. Direction is retained so the
/// painter can reveal RTL runs from the right edge.
@immutable
class KaraokeWordBox {
  final Rect rect;
  final TextDirection direction;

  const KaraokeWordBox(this.rect, this.direction);
}

/// Bounded per-view cache for expensive karaoke text layout and word geometry.
///
/// Entries are keyed by lyric-line index and validated against every property
/// that affects text measurement. Access promotes an entry to the MRU end.
class KaraokeLayoutCache {
  KaraokeLayoutCache({this.maxEntries = 16}) {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive');
    }
  }

  final int maxEntries;
  final LinkedHashMap<int, _KaraokeLayoutEntry> _entries =
      LinkedHashMap<int, _KaraokeLayoutEntry>();
  bool _disposed = false;

  /// Returns whether a matching layout is already prepared.
  ///
  /// This lets the widget render a lightweight Text fallback for one frame
  /// instead of performing a cold TextPainter layout from CustomPainter.paint.
  bool contains({
    required int lineIndex,
    required String text,
    required List<String> wordTexts,
    required double maxWidth,
    required double fontSize,
    required double textScaleFactor,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required Color activeColor,
    required Color dimColor,
  }) {
    if (_disposed) return false;
    final existing = _entries[lineIndex];
    if (existing == null ||
        !existing.matches(
          text: text,
          wordTexts: wordTexts,
          maxWidth: maxWidth,
          fontSize: fontSize,
          textScaleFactor: textScaleFactor,
          textAlign: textAlign,
          textDirection: textDirection,
          activeColor: activeColor,
          dimColor: dimColor,
        )) {
      return false;
    }
    _entries.remove(lineIndex);
    _entries[lineIndex] = existing;
    return true;
  }

  /// Returns an existing layout when the line and its typography are
  /// unchanged; otherwise creates and caches a new layout.
  KaraokeLineLayout obtain({
    required int lineIndex,
    required String text,
    required List<String> wordTexts,
    required double maxWidth,
    required double fontSize,
    required double textScaleFactor,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required Color activeColor,
    required Color dimColor,
  }) {
    if (_disposed) {
      throw StateError('KaraokeLayoutCache has been disposed');
    }
    if (!maxWidth.isFinite || maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'Must be finite and positive');
    }

    final existing = _entries[lineIndex];
    if (existing != null &&
        existing.matches(
          text: text,
          wordTexts: wordTexts,
          maxWidth: maxWidth,
          fontSize: fontSize,
          textScaleFactor: textScaleFactor,
          textAlign: textAlign,
          textDirection: textDirection,
          activeColor: activeColor,
          dimColor: dimColor,
        )) {
      _entries.remove(lineIndex);
      _entries[lineIndex] = existing;
      return existing.layout;
    }

    if (existing != null) {
      _entries.remove(lineIndex);
      existing.layout.dispose();
    }

    final layout = _createLayout(
      text: text,
      wordTexts: wordTexts,
      maxWidth: maxWidth,
      fontSize: fontSize,
      textScaleFactor: textScaleFactor,
      textAlign: textAlign,
      textDirection: textDirection,
      activeColor: activeColor,
      dimColor: dimColor,
    );
    _entries[lineIndex] = _KaraokeLayoutEntry(
      layout: layout,
      text: text,
      wordTexts: wordTexts,
      maxWidth: maxWidth,
      fontSize: fontSize,
      textScaleFactor: textScaleFactor,
      textAlign: textAlign,
      textDirection: textDirection,
      activeColor: activeColor,
      dimColor: dimColor,
    );

    while (_entries.length > maxEntries) {
      final oldestIndex = _entries.keys.first;
      _entries.remove(oldestIndex)!.layout.dispose();
    }

    return layout;
  }

  /// Releases all native paragraph resources while keeping this cache usable.
  void clear() {
    if (_disposed) return;
    for (final entry in _entries.values) {
      entry.layout.dispose();
    }
    _entries.clear();
  }

  /// Releases every cached TextPainter. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    clear();
    _disposed = true;
  }

  KaraokeLineLayout _createLayout({
    required String text,
    required List<String> wordTexts,
    required double maxWidth,
    required double fontSize,
    required double textScaleFactor,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required Color activeColor,
    required Color dimColor,
  }) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      color: dimColor,
      height: 1.4,
    );
    TextPainter? basePainter;
    TextPainter? highlightPainter;

    try {
      basePainter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: TextScaler.linear(textScaleFactor),
      )..layout(maxWidth: maxWidth);

      highlightPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(color: activeColor),
        ),
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: TextScaler.linear(textScaleFactor),
      )..layout(maxWidth: maxWidth);

      final rectsList = <List<KaraokeWordBox>>[];
      var searchFrom = 0;
      for (final word in wordTexts) {
        if (word.isEmpty) {
          rectsList.add(const []);
          continue;
        }
        final index = text.indexOf(word, searchFrom);
        if (index < 0) {
          rectsList.add(const []);
          continue;
        }
        searchFrom = index + word.length;
        final boxes = basePainter.getBoxesForSelection(
          TextSelection(baseOffset: index, extentOffset: searchFrom),
        );
        rectsList.add(
          boxes
              .map((box) => KaraokeWordBox(box.toRect(), box.direction))
              .toList(growable: false),
        );
      }

      return KaraokeLineLayout(
        basePainter: basePainter,
        highlightPainter: highlightPainter,
        wordBoxes: List<List<KaraokeWordBox>>.unmodifiable(rectsList),
      );
    } catch (_) {
      basePainter?.dispose();
      highlightPainter?.dispose();
      rethrow;
    }
  }
}

class _KaraokeLayoutEntry {
  final KaraokeLineLayout layout;
  final String text;
  final List<String> wordTexts;
  final double maxWidth;
  final double fontSize;
  final double textScaleFactor;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final Color activeColor;
  final Color dimColor;

  const _KaraokeLayoutEntry({
    required this.layout,
    required this.text,
    required this.wordTexts,
    required this.maxWidth,
    required this.fontSize,
    required this.textScaleFactor,
    required this.textAlign,
    required this.textDirection,
    required this.activeColor,
    required this.dimColor,
  });

  bool matches({
    required String text,
    required List<String> wordTexts,
    required double maxWidth,
    required double fontSize,
    required double textScaleFactor,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required Color activeColor,
    required Color dimColor,
  }) {
    return this.text == text &&
        identical(this.wordTexts, wordTexts) &&
        this.maxWidth == maxWidth &&
        this.fontSize == fontSize &&
        this.textScaleFactor == textScaleFactor &&
        this.textAlign == textAlign &&
        this.textDirection == textDirection &&
        this.activeColor == activeColor &&
        this.dimColor == dimColor;
  }
}
