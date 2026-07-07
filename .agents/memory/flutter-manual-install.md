---
name: Flutter 3.44.4 manual install
description: Flutter diinstall manual karena Nix hanya sedia 3.32.0; cara recovery kalau SDK hilang.
---

# Flutter 3.44.4 Manual Install

## Rule
Semua perintah `flutter` di workflow dan script harus pakai:
```
export PATH="/home/runner/flutter/bin:$PATH"
```
karena Nix default masih 3.32.0, dan `/home/runner/flutter/bin` harus di depan PATH.

**Why:** Replit Nix channel `stable-25_05` hanya menyediakan Flutter 3.32.0 via `pkgs.flutter`. Tidak ada module Flutter lain yang bisa dipilih lewat `listAvailableModules`. SDK 3.44.4 diinstall manual ke `/home/runner/flutter/`.

**How to apply:**
- Workflow `.replit`: sudah dikonfigurasi dengan prefix PATH di setiap `flutter` command.
- Script JS (`rebuild-web.js`): sudah pakai `env: { PATH: /home/runner/flutter/bin:... }` di spawn options.
- `watch-rebuild.js`: sudah pakai `FLUTTER_BIN = '/home/runner/flutter/bin/flutter'` hardcoded.
- `.replit` deployment build command: sudah pakai prefix PATH.

## Recovery kalau SDK hilang
`/home/runner/flutter/` berada di luar git repo — bisa hilang kalau environment di-reset Replit. Kalau `flutter` tiba-tiba balik ke 3.32.0 atau error not found:
```bash
bash setup-flutter.sh
```
Script ini ada di root workspace dan otomatis download + install Flutter 3.44.4.

## Deprecation fixes yang dilakukan saat upgrade ke 3.44.4
- `SizeTransition.axisAlignment: -1.0` → `alignment: Alignment(0, -1.0)` (dua file)
- `ReorderableListView.onReorder` → `onReorderItem` (dua file); `onReorderItem` sudah adjust newIndex, tidak perlu manual `-1`; untuk `AudioService.reorderQueue` yang masih pakai konvensi lama, reverse-adjust dulu: `n >= o ? n + 1 : n`.
