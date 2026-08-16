# Log System Audit — 2026-08-16

## Scope

Audit read-only menyeluruh terhadap **seluruh sistem logging** aplikasi:

- **Dart core:** `lib/services/log_service.dart` + parts (`level.dart`, `entry.dart`,
  `service.dart`, `native_log_bridge.dart`).
- **UI log:** `lib/pages/log_page.dart` + parts (`app_bar_badge.dart`, `bar_btn.dart`,
  `entry_tile.dart`, `filter_bar.dart`, `log_level_selector.dart`), entry Settings →
  Log Aktivitas (`lib/pages/settings_page/system.dart`).
- **Native log stream:** `android/.../events/EventEmitter.kt` (`object NativeLogger`),
  registrasi channel `musicplayer/native_logs` di `MainActivity.kt:321-322`,
  `diagnostics/CrossfadeTimelineLogger.kt`.
- **Semua 118 situs `NativeLogger.emit`** dan **semua 58 situs `Log.*` logcat-only**
  di 15 file Kotlin, plus **semua caller `LogService.*`** di lib/ (kueri: 22 file Dart).

Tidak ada kode yang diubah. Setiap finding diberi verdict: **Confirmed bug** /
**Confirmed weakness** / **Runtime-only** / **False positive**.

---

## Arsitektur sistem log (verified)

```
Kotlin (thread mana pun)                     Dart (main isolate)
─────────────────────────                    ──────────────────────────
NativeLogger.emit(level, cat, msg)  ──────►  EventChannel "musicplayer/native_logs"
  @Volatile sink                             NativeLogBridge.init() subscribe
  dispatch → main Looper                     └─ switch(level): error→ERR, warn→WRN,
  runCatching { sink?.success }                  verbose→VRB, *default→INF*   ← L-1
                                             LogService.log(cat, msg, level)
                                               └─ _logs Queue (ring 5000)
                                               └─ logCount ValueNotifier
                                             LogPage (listener logCount)        ← L-2
                                               └─ _filtered = getLogs(...) O(n)
                                               └─ 5× countByLevel(...) O(n)
```

- Channel terdaftar di **MainActivity** (bukan service) → subscription tidak putus
  saat service restart. ✅
- `NativeLogger.emit` aman dipanggil dari audio thread (main-looper dispatch +
  `runCatching`). ✅

---

## Findings

### L-1 (P3) — Level `"debug"` dari native di-mapping ke **INFO** di Dart → filter level menyesatkan

**File / class / line:**
- `lib/services/log_service/native_log_bridge.dart:31-39` — `switch (level)` tanpa case
  `'debug'` → jatuh ke default `LogLevel.info`.
- `lib/services/log_service/level.dart` — enum `LogLevel` tidak punya `debug`.

**Evidence:**
- **10 situs Kotlin emit `"debug"`**: `Media3PlaybackService.kt:809, 1489, 1495`,
  `PlaybackNotificationManager.kt:201, 350`, `SessionArtworkProvider.kt:202, 226, 244,
  255, 312`.

**Dampak nyata:**
- Intent developer (debug = lebih rinci dari info) hilang di UI. Mode **Verbose-only**
  tidak menyembunyikan debug; mode **Errors-only** juga tidak memfilternya secara
  khusus — keduanya tampil sebagai INF.
- Filter level di LogPage tidak bisa memisahkan info dari debug.

**Counter-evidence:** Tidak ada incorrect behavior — pesan tetap tampil, hanya label
dan filterability yang salah.

**Verdict:** **Confirmed weakness.** Perbaikan minimal: tambahkan case `'debug'` →
`LogLevel.verbose` (atau tambah enum `LogLevel.debug` + tag `DBG`).

---

### L-2 (P3) — LogPage rebuild penuh O(n) per log event → jank saat burst log

**File / class / line:**
- `lib/pages/log_page.dart` — `_LogPageState._onNewLog` (:86-98), `_filtered` getter
  (:120-124), `_countLevel` (:126) → `LogService.countByLevel`.

**Evidence:**
- `_onNewLog` dipanggil dari `LogService.logCount.addListener` **untuk setiap log baru**
  dan melakukan `setState(_expanded.clear)`.
- Build berikutnya mengeksekusi: `_filtered` = `getLogs(...)` = scan O(n) atas ring
  buffer, **plus** `_countLevel` × 5 = 5× scan O(n). Dengan 5000 entri ≈ 30.000
  iterasi per event log.
- Burst nyata yang reachable: CrossfadeTimelineLogger meng-emit **±30 baris per
  crossfade** (verified di `CrossfadeController.kt`), restore queue, prewarm artwork,
  scan ReplayGain batch.

**Dampak nyata:** LogPage terbuka + logging ON + burst → rebuild bertumpuk, jank
scrolling. Tidak ada debounce/throttle.

**Verdict:** **Confirmed weakness** (performance, UI-only saat LogPage terbuka).
Perbaikan: debounce `_onNewLog` (mis. 100–200 ms) dan/atau cache count per level.

---

### L-3 (P3) — 58 situs `Log.*` logcat-only tidak tampil di in-app viewer — termasuk `Log.e` kritis

**File / class / line:**
- 15 file: `MetadataCacheDb.kt` (9), `ReplayGainBridge.kt` (7), `NativePaletteBridge.kt`
  (7), `FallbackBitmapLoader.kt` (7), `ArtworkCacheManager.kt` (5),
  `MediaStoreWriteGate.kt` (4), `MetadataPrescanner.kt` (4),
  `SignalsmithStretchAudioProcessor.kt` (4), `MainActivity.kt` (4),
  `ExoMetadataReader.kt` (3), `NativeDspAudioProcessor.kt` (2), `ReplayGainService.kt`
  (1), `StereoWideningAudioProcessor.kt` (1).

**Evidence — error terpenting yang hilang dari viewer:**
- `ReplayGainBridge.kt:344, 349, 354, 361, 366` — `Log.e` jalur write→verify→rollback:
  "mutation failed without a metadata backup", "could not reopen for rollback",
  "rollback failed", "rollback verification failed". Error kritis data-integrity ini
  **hanya di logcat** — user/dev yang debugging via Log Aktivitas tidak akan melihatnya.
- Sisanya `Log.w`/`Log.d` I/O cache (MetadataCacheDb, ArtworkCacheManager) dan probe
  (NativePaletteBridge, MainActivity).

**Catatan:** Sistem log jelas berusaha memusatkan native logs ke viewer (118 situs
`NativeLogger.emit` sudah terhubung), tapi 58 situs masih bypass.

**Verdict:** **Confirmed weakness** (konsistensi + observability gap). Tidak ada
incorrect behavior — logcat tetap menerima semuanya.

---

### L-4 (P4) — `LogService.warn('Permissions', …)` dijalankan **sebelum** `LogService.init()` → selalu di-drop

**File / class / line:**
- `lib/main/main.dart` — `_requestAudioPermission()` dipanggil sebelum
  `Future.wait([... LogService.init() ...])`.
- `lib/services/log_service/service.dart` — `log()` return early ketika
  `loggingEnabled.value == false` (nilai awal).

**Dampak nyata:** Satu pesan hilang **selalu** (bahkan ketika user pernah mengaktifkan
logging), karena prefs `log_enabled` belum dibaca saat permission request selesai.

**Verdict:** **Confirmed weakness** (1 baris, tidak berdampak fungsional). Perbaikan:
pindahkan panggilan setelah `LogService.init()` atau inisialisasi `loggingEnabled`
sinkron.

---

### L-5 (P4) — Setiap log baru me-reset stack-trace expansion user + live-tail menyela

**File / class / line:**
- `lib/pages/log_page.dart` — `_onNewLog` → `setState(_expanded.clear)` + `animateTo(0)`
  saat `_liveTail` (default **ON**).

**Dampak nyata:** Saat user membuka stack trace entry lama, satu log baru masuk →
expansion hilang dan list melompat ke atas. Ada toggle live-tail, jadi bisa
dimatikan, tapi default-nya mengganggu alur baca log lama.

**Verdict:** **Confirmed weakness** (UX minor). Perbaikan: jangan clear expansion
kecuali entry yang di-expand ter-evict dari ring buffer.

---

### L-6 (Note) — `countByLevel` global tidak mengikuti filter aktif

**File / class / line:**
- `lib/pages/log_page.dart:126` → `LogService.countByLevel` (scan seluruh buffer,
  bukan hasil filter).

**Dampak:** Angka di chip level statis terhadap total buffer, tidak berubah saat
search/category filter aktif. Informational, bukan bug.

---

### L-7 (Note) — Memory ring buffer: stack trace penuh per error

**File / class / line:**
- `lib/services/log_service/service.dart` — `_maxEntries = 5000`, `LogEntry.stackTrace`.

**Dampak:** 5000 × (message + stackTrace). Dalam error storm (Flutter/Dart error
berulang), dapat mencapai puluhan MB. Ada batas (5000) jadi bounded. Tidak ada
persistence ke disk — kosong setelah restart.

---

## Verified strengths

- **Logging tidak bisa crash playback** — `NativeLogger.emit` di-dispatch ke main
  Looper dengan `runCatching`; historisnya memperbaiki
  `ExceptionInInitializerError`/`NoClassDefFoundError` saat emit dari audio thread
  (dokumentasi di `EventEmitter.kt`). ✅
- **Tidak ada emit per-frame/per-buffer di hot path audio** — seluruh 118 situs
  `NativeLogger.emit` (termasuk 21 di SignalsmithStretchAudioProcessor) bersifat
  state-transition, bukan per-sample/per-buffer; guard
  `lastNativeFailureResult != result` mencegah log spam pada failure berulang. ✅
- **Ring buffer bounded** (5000, `removeFirst()` O(1)). ✅
- **Default OFF** (`log_enabled=false`) → overhead produksi nol. ✅
- **Error capture 3 jalur lengkap:** zone handler `runZonedGuarded` (fallback
  `debugPrint` sebelum init), `FlutterError.onError`, `PlatformDispatcher.onError`. ✅
- **NativeLogBridge idempotent** (cancel-subscription sebelum subscribe ulang);
  channel terdaftar di MainActivity → tidak ada reconnect bug saat service
  start/stop. ✅
- **CrossfadeTimelineLogger ter-wire penuh** — `begin()` di `beginCrossfade`,
  `end()` di cancel/abort/complete; semua jalur abort mid-fade tercakup
  (`CrossfadeController.kt:204, 247, 413, 476`). ✅
- **LogPage fungsional lengkap:** filter level/kategori/search, copy entry/all, clear
  dengan konfirmasi, live-tail toggle, expand stack trace, badge error/warn count. ✅
- **Kategori konsisten** antara native dan Dart (Media3, AudioService, AudioEffects,
  ReplayGain, SleepTimer, dst.) — memudahkan filter. ✅

---

## Test gap

Tidak ada unit test untuk: ring buffer + filter `getLogs` (boundary 5000, eviction),
mapping level native→Dart di `NativeLogBridge` (khususnya `'debug'` — L-1), dan widget
test LogPage (filter, live-tail, expand).

---

## Verification

- Verifikasi statis menyeluruh: 118 situs `NativeLogger.emit`, 58 situs `Log.*`, semua
  caller `LogService.*` dibaca dalam konteks.
- `flutter analyze` (baseline turn sebelumnya): **No issues found** — tidak ada kode
  yang diubah pada audit ini.
- Android SDK tidak tersedia → Kotlin diverifikasi statis (tidak dikompilasi).
- Tidak ada runtime device validation (Mi 9T) di environment ini.

## Audit conclusion

Sistem logging sudah dirancang dan diimplementasikan dengan baik: thread-safe di
native, bounded di Dart, default-off, error capture lengkap, dan viewer yang
fungsional. **Tidak ada Confirmed bug** — semua temuan adalah **Confirmed weakness**
(P3–P4) yang tidak menghasilkan incorrect behavior pada jalur produksi. Prioritas
perbaikan: **L-1** (mapping level debug → info, 1 baris), **L-2** (debounce LogPage),
**L-3** (migrasi `Log.e` ReplayGainBridge ke `NativeLogger.emit` agar kegagalan
rollback terlihat di viewer), lalu L-4/L-5 (minor).
