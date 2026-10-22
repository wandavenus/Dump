import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/utils/palette_contrast.dart';

void main() {
  test('dark palette colors keep white text', () {
    const background = Color(0xFF2B313A);

    expect(paletteForegroundColor(background), Colors.white);
    expect(paletteSecondaryForegroundColor(background), Colors.white70);
  });

  test('light palette colors switch to dark text', () {
    const background = Color(0xFFFFFFFF);

    expect(paletteForegroundColor(background), Colors.black87);
    expect(paletteSecondaryForegroundColor(background), Colors.black54);
  });

  test('mid-gray uses the W3C luminance switch point', () {
    const background = Color(0xFF808080);

    expect(background.computeLuminance(), greaterThan(0.179));
    expect(paletteForegroundColor(background), Colors.black87);
  });
}
