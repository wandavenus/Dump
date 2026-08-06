import 'package:flutter/material.dart';

/// Resolves the base direction for one lyric line.
///
/// Arabic lyrics can contain Latin words, artist names, or punctuation. When
/// Arabic script is present, use RTL as the paragraph direction so the line
/// stays on the right while Flutter's bidi layout handles embedded LTR runs.
class LyricsTextDirection {
  LyricsTextDirection._();

  static TextDirection resolve(String text) {
    for (final rune in text.runes) {
      if (isArabicRune(rune)) return TextDirection.rtl;
    }
    return TextDirection.ltr;
  }

  static bool isArabicRune(int rune) {
    // Only strong Arabic letters should decide paragraph direction. Arabic
    // punctuation and digits can appear in an otherwise LTR line.
    return rune >= 0x0621 && rune <= 0x063A ||
        rune >= 0x0641 && rune <= 0x064A ||
        rune >= 0x066E && rune <= 0x066F ||
        rune >= 0x0671 && rune <= 0x06D3 ||
        rune >= 0x06FA && rune <= 0x06FC ||
        rune >= 0x0750 && rune <= 0x077F ||
        rune >= 0x08A0 && rune <= 0x08FF ||
        rune >= 0xFB50 && rune <= 0xFDFF ||
        rune >= 0xFE70 && rune <= 0xFEFF ||
        rune >= 0x1EE00 && rune <= 0x1EEFF;
  }
}
