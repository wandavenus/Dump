---
name: Liquid Glass iOS 27 architecture
description: Arsitektur sistem Liquid Glass — ThemeController, LiquidGlass widget, per-komponen notifier, dan cara WebView harus diubah agar background blur berfungsi.
---

## Aturan

### ThemeController
- Master: `glassTheme` (ValueNotifier<bool>)
- Per-komponen: `glassNavBar`, `glassAppBar`, `glassMiniPlayer`, `glassCards`
- Semua disimpan di SharedPreferences dengan key `glass_*`
- Gunakan `ThemeController.allGlass` (Listenable.merge) di ListenableBuilder agar halaman rebuild saat komponen mana pun berubah

### WebView (webViewContainer.dart)
Saat glass ON: `innerContainerColor = transparent` dan gunakan dark blue-black gradient sebagai background (`#141B2D` → `#090D16`). Ini wajib agar BackdropFilter di elemen glass punya sesuatu untuk di-blur. Tanpa ini, blur di atas solid black = tidak terlihat.

**Why:** BackdropFilter hanya blur konten yang dirender sebelumnya di layer yang sama. Jika background solid hitam, blur = hitam. Dengan gradient biru-gelap yang terekspos (karena WebView transparent), glass jadi terlihat berwarna.

### LiquidGlass widget
- `LiquidGlass` — panel rounded: ClipRRect + BackdropFilter + gradient white overlay (topLeft 0.30, mid 0.10, bottomRight 0.04) + Border.all white 0.22
- `LiquidGlassBar` — bar full-width (ClipRect, bukan ClipRRect): untuk AppBar dan MiniPlayer
- `LiquidGlassPill` — capsule shape untuk chip/tombol kecil
- Blur sigma: 24 untuk panel, 20 untuk bar

### Cara menerapkan glass ke AppBar
Gunakan `AppBar.flexibleSpace = LiquidGlassBar()` + `AppBar.backgroundColor = transparent`. Jangan gunakan `extendBodyBehindAppBar` (menyebabkan layout issue dengan content overlap).

### Setiap halaman
Bungkus Scaffold dalam `ListenableBuilder(listenable: ThemeController.allGlass)`. Set `Scaffold.backgroundColor = transparent` saat glass on untuk mengekspos WebView gradient.

### Full player DIKECUALIKAN
`player_sheet.dart` dan `mini_player.dart` (expanded state) tidak mendapat treatment glass — keduanya punya desain visual sendiri.

**How to apply:** Saat menambah halaman/komponen baru, pakai pattern yang sama: `ListenableBuilder(listenable: ThemeController.allGlass, ...)` untuk rebuild, dan cek `ThemeController.isXxxGlass` untuk pilih antara glass/solid.
