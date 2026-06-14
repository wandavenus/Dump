---
name: LogService persistent
description: LogService.init() membaca SharedPrefs untuk loggingEnabled dan errorsOnly; max 500 entri; harus diinit di main() sebelum AudioEngine.
---

## Init Order di main()
```dart
await ThemeController.init();
await LogService.init();       // ← sebelum AudioEngine
await AudioEngine.initialize();
await AudioEffectsService.init();
```

## Toggles
- `loggingEnabled`: jika false, semua log diabaikan dan _logs dibersihkan
- `errorsOnly`: jika true, level INFO diabaikan (hanya WARNING + ERROR disimpan)
- Keduanya persist ke SharedPrefs dengan key `log_enabled` dan `log_errors_only`

## Kapasitas
- Max 500 entri; `_logs.removeAt(0)` saat penuh (FIFO)
- `kDebugMode` guard untuk `debugPrint` — tidak print di release build

**Why:** Logging perlu bisa dimatikan untuk battery/privacy; errorsOnly mode berguna untuk produksi di mana info logs terlalu banyak.
