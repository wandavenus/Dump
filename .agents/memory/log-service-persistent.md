---
name: LogService persistent
description: LogService.init() reads SharedPrefs for loggingEnabled, errorsOnly, verbose, and live-tail; ring buffer 5000 entries with priority eviction and redaction.
---

## Init Order di main()
```dart
await ThemeController.init();
await LogService.init();       // ← sebelum AudioEngine
await AudioEngine.initialize();
await AudioEffectsService.init();
```

## Toggles
- `loggingEnabled`: jika false, semua log diabaikan dan `_logs` dibersihkan.
- `errorsOnly`: jika true, hanya WARNING + ERROR disimpan.
- `verboseEnabled`: jika false, level VERBOSE diabaikan.
- `liveTailEnabled`: mengontrol auto-scroll halaman log.
- Semua persist ke SharedPrefs (`log_enabled`, `log_errors_only`, `log_verbose`, `log_live_tail`).

## Kapasitas & notifikasi
- Max **5000** entri. Saat penuh, entri verbose/info tertua dibuang lebih dulu; error/warn dipertahankan selama masih ada entri non-warning.
- `logCount` adalah jumlah entri (mentok di 5000). `logRevision` adalah counter monotonik untuk memberi tahu UI bahwa ada entri baru; halaman log WAJIB listen ke `logRevision`, bukan `logCount`.
- `clear()` menaikkan `logRevision` agar live tail ikut ter-reset.

## Privasi & kategori
- `LogRedaction.apply` meredaksi URI (`content://`, `file://`, `http(s)://`, `rtsp://`, `ftp://`) dan path absolut perangkat menjadi `<uri>`/`<path>` pada message dan stack trace.
- Jangan menaruh judul/artis lagu, path lirik, path AutoMix, atau URI file di log. Gunakan `song.id` atau status generik.
- Alias kategori dinormalisasi di `LogService` (mis. `AudioEffects/PlaybackManager/MediaCap → Audio`, `FetchManager/LocalFileProvider → Lyrics`, `ReplayGainApplicator/LoudnessResolver → ReplayGain`, widget cards → `UI`). Filter UI memakai kategori hasil normalisasi.

## Native bridge
- `NativeLogger` Kotlin juga meredaksi sebelum logcat dan emit. `debugLog` hanya logcat; `infoLog`/`warnLog`/`errorLog` diteruskan ke viewer.
- Jangan menambah `NativeLogger.emit` tepat setelah `warnLog`/`errorLog`/`infoLog` — akan duplikat.

**Why:** Logging harus bisa dimatikan untuk battery/privacy; errorsOnly berguna di produksi; buffer yang penuh tidak boleh menghentikan live tail atau membuang error penting.
