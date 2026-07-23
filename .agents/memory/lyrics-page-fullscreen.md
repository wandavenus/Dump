---
name: LyricsPage full-screen
description: LyricsPage adalah full-screen Scaffold (bukan modal); dibuka via PageRouteBuilder SlideTransition dari bawah.
---

## Routing
```dart
Navigator.of(context).push(PageRouteBuilder(
  opaque: false,
  transitionDuration: Duration(milliseconds: 380),
  pageBuilder: (_, __, ___) => LyricsPage(song: song),
  transitionsBuilder: (_, animation, __, child) => SlideTransition(
    position: Tween(begin: Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
));
```

## Layout (Stack)
1. `_LyricsBackground` — album art blur (AnimatedBlurredPlayerBackground pattern)
2. `BackdropFilter` + `ColoredBox` — overlay gelap + extra blur (dari LyricsSettings)
3. `_EdgeGradients` — gradient atas/bawah untuk readability
4. Column: `_LyricsHeader` + `_LyricsBody` atau `_EmptyLyrics`

## _LyricsHeader
- Tombol kiri: chevron_down → Navigator.pop()
- Tengah: judul + artis lagu
- Tombol kanan: textformat icon → showModalBottomSheet `_LyricsAppearanceSheet`

## _LyricsAppearanceSheet
Semua kontrol di sini; live preview karena ValueListenable:
- FontSizePicker (S/M/L/XL toggle chips)
- AlignPicker (kiri/tengah/kanan icon chips)
- ColorPicker (putih/merah/kuning)
- DimSlider + BlurSlider
- Sumber lirik toggle

**Why:** Full-screen lebih baik dari modal untuk konten panjang (lirik); bisa overlay album art penuh tanpa constraint height modal.
