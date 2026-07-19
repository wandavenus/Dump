# M-6 — NativeModuleRegistry Initialization Audit Report

**Tanggal:** 19 Juli 2026  
**Hasil:** Keep sequential — no code changes required

---

## 1. Dependency Report

### Modul Terdaftar

Hanya 2 modul yang terdaftar di `PlaybackManager.initialize()`:

```
NativeModuleRegistry.register(NativeDspBridge.instance);    // slot 0
NativeModuleRegistry.register(FfmpegDecoderBridge.instance); // slot 1
```

---

### NativeDspBridge (`native_dsp`)

| Aspek | Detail |
|---|---|
| **Tujuan** | Jembatan FFI ke `native_audio_runtime` C library; mendaftarkan diri ke runtime untuk DSP future use |
| **Resource yang di-acquire** | FFI handle ke native `.so` via `NativeAudioRuntime.instance.initialize()` |
| **Blocking** | Ya — `await NativeAudioRuntime.instance.initialize()` adalah FFI load nyata |
| **Side effect** | Memuat native library ke proses; memanggil `registerModule()` ke runtime |
| **Shared state** | `NativeAudioRuntime.instance` (singleton) |
| **JNI** | Tidak — ini FFI (Dart native assets), bukan JNI |
| **Idempotent** | Ya — `_status != uninitialized` guard di awal |
| **Depends on** | Tidak ada modul lain |
| **Dependency of** | Tidak ada modul lain |
| **Kategori** | **A — Independent** |

---

### FfmpegDecoderBridge (`ffmpeg_decoder`)

| Aspek | Detail |
|---|---|
| **Tujuan** | Query runtime availability FFmpeg decoder (via Kotlin reflection), subscribe ke decoder-info events |
| **Resource yang di-acquire** | EventChannel subscription (`musicplayer/ffmpeg_decoder_events`) |
| **Blocking** | **Tidak** — `initialize()` return immediately; probe MethodChannel dijalankan `unawaited` di background dengan timeout 3s |
| **Side effect** | Membuka EventChannel broadcast stream; fires background MethodChannel call |
| **Shared state** | Tidak menyentuh `NativeAudioRuntime` sama sekali; state pribadi (`_capabilities`, `_status`) |
| **JNI** | Native probe ada di Kotlin (`FfmpegCapabilityProbe.kt`), tapi Dart-side tidak tahu — hanya MethodChannel round-trip |
| **Idempotent** | Ya — `_status != uninitialized` guard di awal |
| **Depends on** | Tidak ada modul lain |
| **Dependency of** | Tidak ada modul lain |
| **Kategori** | **A — Independent** |

---

### Dependency Graph

```
NativeDspBridge          FfmpegDecoderBridge
      │                         │
      ▼                         ▼
NativeAudioRuntime.init()   MethodChannel (unawaited, bg)
  (FFI, real blocking)      (returns instantly)

Tidak ada edge antara kedua modul.
```

---

## 2. Keputusan: **Keep Sequential**

### Alasan

Meskipun kedua modul termasuk **Category A** (tidak ada dependency satu sama lain), parallelisasi via `Future.wait()` tidak memberikan manfaat:

1. **`FfmpegDecoderBridge.initialize()` sudah return instantly.**  
   Probe MethodChannel dijalankan `unawaited` di background dengan timeout 3s.  
   Dalam loop sequential saat ini, slot FFmpeg memakan **~0ms**.  
   `Future.wait([dsp.init(), ffmpeg.init()])` tidak menghemat waktu.

2. **Satu-satunya blocking call adalah `NativeDspBridge`.**  
   FFI library load tidak bisa diparalelkan dengan dirinya sendiri.  
   Menjalankannya bersama FFmpeg (yang sudah non-blocking) tidak mengubah critical path.

3. **Kompleksitas vs. manfaat tidak seimbang.**  
   `Future.wait()` menghilangkan per-module error isolation yang saat ini ada di `NativeModuleRegistry.initializeAll()` (setiap module di-catch secara independen). Untuk mengembalikan isolation, perlu wrapping per-future — lebih verbose, lebih banyak kode, nol keuntungan waktu.

4. **Komentar di kode sudah mengantisipasi ini.**  
   `NativeDspBridge.dispose()` berisi komentar: *"Do NOT dispose the shared NativeAudioRuntime here — FfmpegDecoderBridge (or a future module) may still be using it."* Ini menunjukkan arsitektur sudah dirancang dengan shared lifecycle yang dikelola sequential registry.

### Jika modul baru ditambahkan di masa depan

Jika ada modul baru yang:
- Juga Category A (tidak ada dependency), DAN
- Benar-benar blocking (bukan `unawaited` probe), DAN
- Waktu init-nya signifikan (>100ms)

Baru pertimbangkan hybrid pattern:

```dart
// Contoh hybrid jika ada 3+ modul independen dan blocking:
await Future.wait([moduleA.initialize(), moduleB.initialize()]);
await moduleCThatDependsOnAB.initialize();
```

---

## 3. Changed Files

**Tidak ada.** Tidak ada perubahan kode.

---

## 4. Validation

Tidak diperlukan runtime verification karena tidak ada perubahan kode.

Static analysis:
```
flutter analyze --no-pub → No issues found
```

---

## Ringkasan

| Modul | Kategori | Blocking | Decision |
|---|---|---|---|
| `NativeDspBridge` | A — Independent | Ya (FFI load) | Tetap sequential |
| `FfmpegDecoderBridge` | A — Independent | Tidak (unawaited probe) | Tetap sequential |

**Verdict:** `NativeModuleRegistry.initializeAll()` sequential loop sudah optimal untuk jumlah dan karakter modul saat ini. M-6 ditutup sebagai "no change needed".
