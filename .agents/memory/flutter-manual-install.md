---
name: Flutter 3.44.5 manual install
description: Flutter diinstall manual karena Nix hanya sedia 3.32.0; cara recovery kalau SDK hilang.
---

# Flutter 3.44.5 Manual Install

## Rule
Semua perintah `flutter` di workflow dan script harus pakai full path atau prefix PATH:
```
export PATH="/home/runner/flutter/bin:$PATH"
```
karena Nix default masih 3.32.0, dan `/home/runner/flutter/bin` harus di depan PATH.

**Why:** Replit Nix channel `stable-25_05` hanya menyediakan Flutter 3.32.0 via `pkgs.flutter`. Tidak ada module Flutter lain yang bisa dipilih lewat `listAvailableModules`. SDK 3.44.5 disiapkan manual, lalu salinan workspace dipakai agar cache SDK dapat ditulis.

**How to apply:**
- Workflow `.replit`: setiap flutter command diawali `bash setup-flutter.sh && export PATH=...`
- Build APK memakai `/home/runner/workspace/flutter-ws/flutter`, salinan yang dibuat atomik oleh setup script.
- `rebuild-web.js` dan `watch-rebuild.js` harus memakai path SDK yang sudah dikonfigurasi project.
- `.replit` deployment build command: sudah pakai prefix PATH.

## Recovery kalau SDK hilang (OTOMATIS)
Setiap workflow yang pakai flutter menjalankan `bash setup-flutter.sh` sebagai langkah pertama.
Script ini cepat kalau sudah ada (cek binary, langsung exit), dan otomatis download+install kalau tidak ada.
Jadi environment reset = tidak masalah, workflow berikutnya akan reinstall sendiri.

Kalau mau manual:
```bash
bash setup-flutter.sh
```

## Deprecation fixes saat upgrade ke 3.44.x
- `SizeTransition.axisAlignment: -1.0` → `alignment: Alignment(0, -1.0)` (dua file)
- `ReorderableListView.onReorder` → `onReorderItem` (dua file); `onReorderItem` sudah adjust newIndex, tidak perlu manual `-1`; untuk `AudioService.reorderQueue` yang masih pakai konvensi lama, reverse-adjust dulu: `n >= o ? n + 1 : n`.
