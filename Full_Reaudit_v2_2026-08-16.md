# Full Re-Audit v2 — 2026-08-16 (lib + android + native_audio_runtime, state terbaru)

## Scope & method

Permintaan: audit ulang penuh semua kode di `lib/`, `android/`, `native_audio_runtime/`
pada state terbaru, tanpa ada yang terlewat.

Metode:
1. **Baseline**: `git status` (tree bersih, fix terakhir ter-commit di `4c14565`),
   `flutter analyze` → No issues found, `flutter test` → 63/63 pass.
2. **Verifikasi semua temuan audit sebelumnya** langsung ke source (file:line saat ini),
   bukan dari dokumen: RG-1..3, K1–K13, N1–N6, F1–F6, BP-01..09, L-1..7, NR-1..5.
3. **Re-audit perubahan terbaru** dengan fresh eyes: NR-1/NR-2 (per-stream RG gain +
   loudness reset), NR-3..5 (capability table + doc), BP-09 (volume antar player),
   L-6/L-7 (log filter + cap stack trace).
4. **Baca ulang sistematis** area inti di ketiga folder + scan pola bug
   (cast tak aman, `!!`, resource leak, runnable leak, race, cursor/fd leak,
   nullable crash path).
5. **Read-only** — konsisten dengan konvensi audit. Tidak ada kode yang diubah.

Keterbatasan: tidak ada Android SDK → Kotlin/C tidak dikompilasi; verifikasi statis.

---

## 1. Status semua temuan sebelumnya (diverifikasi ulang ke source)

| ID | Verdict | Status saat ini (v2) |
|---|---|---|
| RG-1 | FALSE POSITIVE + race `_inFlight` | **FIXED** — `invalidate()` menghapus `_inFlight` (`replay_gain_service/service.dart:62,121`) ✓ |
| RG-2 | WEAKNESS (mtime granularity FAT32/exFAT) | **OPEN (note)** — by design, device-dependent, tidak diubah |
| RG-3 | WEAKNESS (fsync durability) | **FIXED** — `FsyncGuard` log errno (`tag_writer.cpp`) ✓ |
| K1–K13 | 2×P2 + 11×P3 | **FIXED** ✓ (K5 delete retry + A2 artwork cleanup di `MainActivity.onActivityResult:1007-1035`; K6 `failPending` + onDestroy; K7 `attachGeneration` di `AudioEffectsManager`; K8 dedupe `MetadataCacheDb`; K10 identity artwork; K12 `effectSupportMap`; K13 `leavePreviewMode` di proxy lambdas) |
| N1–N4 | 4×P3 | **FIXED** ✓ (N1 clearCache setelah re-scan; N3 prefetch retry di `playback_manager.dart`) |
| N5 | Note (dua cache RG) | **OPEN (note)** — by design (SQLite native mtime-validated untuk playback, prefs Dart untuk song-info) |
| N6 | Note (gating block ≤400 ms) | **OPEN (note)** — didokumentasikan di header C, self-correcting, inaudible |
| F1–F6 | 3×P2 + 3×P3 | **FIXED** ✓ (F4 `handleStop` cancel timer di `TransportCommands`; F5 rollback optimistik; F6 dead code dihapus) |
| BP-01..BP-08 | 1×P1 + 4×P2 + 3×P3 | **FIXED** ✓ (bit-perfect player, preview suppression, offload, artwork) |
| BP-09 | Note (volume antar player) | **FIXED** ✓ — `ActivePlayerProxy.switchTo:104` menyalin `_current.volume`; gap bit-perfect + crossfade promotion ditutup (lihat §2) |
| L-1..L-5 | 2×P3 + 2×P4 + note | **FIXED** ✓ |
| L-6 | Note (badge filter) | **FIXED** ✓ — `countByLevel(category, search)` + LogPage `_filteredTotal` |
| L-7 | Note (memori stack trace) | **FIXED** ✓ — cap 3000 char per trace di `LogService.log` |
| NR-1 | P3 (per-stream RG gain) | **FIXED** ✓ — `nar_replaygain_set_gain_for_stream` diekspos + `_preloadStandbyDsp` |
| NR-2 | P3 (loudness reset stream-0 only) | **FIXED** ✓ — `nar_loudness_reset_stream` + reset per slot saat promotion & preload |
| NR-3 | P4 (capability table) | **FIXED** ✓ — `dsp.equalizer=0`, `scan.loudness_ebur128=1`, version `phase8.5` |
| NR-4/NR-5 | P4 (doc drift) | **FIXED** ✓ — slot numbering C header + facade Dart dikoreksi (gain=0..soft_clipper=6) |

**Verdict: 0 temuan yang seharusnya fixed ternyata masih ada.**

---

## 2. Re-audit perubahan terbaru (fresh eyes)

### NR-1/NR-2 (per-stream ReplayGain + loudness) — VERIFIED CORRECT
- C: `_rg_process` membaca `_gain_bits[stream_slot]` (`replaygain_processor.c:110`);
  `nar_replaygain_set_gain_for_stream` clamp + atomic store per slot (:205-214).
- C: `nar_loudness_reset_stream` clamp + transient bypass per stream (`loudness_processor.c:768-774`).
- Bindings hand-maintained sinkron dengan C header (nama + signature persis).
- Dart: `_preloadStandbyDsp` (service.dart:385) mengasumsikan standby slot = `1 - activeSlot` —
  **invariant ini terverifikasi di native**: `setStandbyPlayer` selalu menaruh standby di slot
  non-aktif (`Media3PlaybackService.kt:400-403`) dan slot fisik tidak pernah berubah per player.
- Promotion reset/apply menarget slot aktif dari `streamSlot` di currentTrack map
  (`TrackMapper.kt` + `TransportState.getActiveStreamSlot`).
- Fallback `activeSlot = 0` saat key `streamSlot` absen (native lama) — aman (single-player
  setara shared-knob).
- **Tidak ditemukan cacat.** Dedup `_lastPrefetchedIndex` di PlaybackManager tidak terkait
  (prefetch artwork), apply standby di-dedup lewat guard `nativeNext != nextTrackIndex`.

### BP-09 (volume antar player) — VERIFIED CORRECT
- `ActivePlayerProxy.switchTo` menyalin `_current.volume` → `newPlayer` sebelum listener
  migrasi. Semua pemanggil diperiksa:
  - Bit-perfect ON: `_current` = player lama (volume user) → clean player mendapat volume ✓
  - Bit-perfect OFF: `_current` = clean (membawa perubahan volume selama mode) → restored ✓
  - Crossfade begin: `standby.volume = 0f` di-set SEBELUM switchTo; fade tick pertama
    (handler.post, ~16 ms) mengambil alih → interim tidak terdengar ✓
  - Crossfade complete: `newPlayer === _current` → early-return, tidak ada copy ganda ✓
  - Duck aktif: copy = volume ter-duck; fade memakai `effectiveVolume()` (sama) ✓
- **Tidak ditemukan cacat.**

### L-6/L-7 (log) — VERIFIED CORRECT
- `countByLevel(level, category, search)`; LogPage melewati filter aktif; chip ALL =
  `_filteredTotal`. Satu-satunya caller lain (`settings_page/system.dart`) memakai
  `logCount` global — tidak terpengaruh.
- `_capStackTrace` head-3000 + marker; entri lama (≤3000) tidak diubah; `toString()`
  tetap utuh. Memory worst case terbatas.

### NR-3..5 — VERIFIED CORRECT
- Capability table konsisten dengan implementasi (tidak ada `peq_processor.c` di `src/`;
  loudness_processor.c memang EBU R128). Tidak ada konsumen Dart yang key pada
  `dsp.equalizer` / `scan.loudness_ebur128` (hanya debug page generik).
- Slot numbering 0-indexed konsisten di semua header + facade.

---

## 3. Baca ulang sistematis (area inti, verifikasi langsung)

**Dart (`lib/`):**
- `audio_service.dart` + `service.dart` (1015 baris penuh): guard `_isLoading`,
  `_queueMutationGuard` re-sync, timeout syncFromNative (5s/2s/2s), suppressRestoredSong,
  `_onNativeCurrentTrackChanged` resolve id fallback. ✓
- `replay_gain_applicator.dart`: fail-open total, mutual exclusion LoudnessNorm vs
  LoudnessEnhancer sistem (dua arah — `AudioEffectsService.setLoudnessNormEnabled` dan
  `DeviceDsp.applyNormalize`). ✓
- `device_dsp.dart`, `loudness_source_resolver.dart` (`_sameAlbum` fallback string trim
  lower-case — aman), `native_dsp_bridge.dart`, `ffmpeg_decoder_bridge.dart`,
  `native_palette_service.dart` (LRU, in-flight dedup, atomic write tmp→rename,
  D5 dirty-flag guard), `history_service`, `local_song.dart` (fromMap defensif penuh).
- `log_service` + `log_page`: debounce 150 ms di-cancel di dispose, mounted guard,
  `contains()` prune ekspansi. ✓
- `lyrics_service/`: token cancellation, deadline/upgrade timer di-cancel di `finally`,
  failure TTL, provider error tidak menggagalkan yang lain. ✓

**Kotlin (`android/`):**
- `QueueManager`: mutasi ExoPlayer di-skip saat crossfade (`isCrossfadeInProgress`),
  `pendingPlayNextIndex` + `forceNextInShuffleOrder` validasi permutation (size + set +
  index range sebelum `setShuffleOrder`). ✓
- `SleepTimerManager`: runnable selalu di-remove (timer/tick/fade), K11 restore volume
  user, F2 guard crossfade. ✓
- `AudioEffectsManager`: K7 generation guard benar (retry hanya jalan jika
  `expectedGeneration == attachGeneration`), retry berbasis `eqOk` bukan `anyOk`,
  `isEffectTypeAvailable` tidak pernah attach ke session 0 (LOW-03). ✓
- `EventEmitter` (ConcurrentHashMap), `NativeLogger` (volatile sink + dispatcher main
  looper — emit dari thread audio aman), `ServiceReadyGate` (markReady di akhir
  onCreate, reset di onDestroy:1000 — terverifikasi terpanggil). ✓
- `AudioOffloadManager`: observer-only (API Media3 1.11), tidak ada kontrol scheduling
  yang hilang. ✓
- `PlaybackNotificationManager`: per-key in-flight set, generation per key, stale-result
  guard `cacheKey != currentTrackCacheKey()`, `close()` idempotent + guarded post,
  K3 suppression di semua jalur create, K10 path identity, negative TTL 30 s. ✓
- `ReplayGainService`: session EburTrackSession selalu di-close (`finally`), hasil
  invalid ditolak, write→verify→rollback lengkap. `ReplayGainBridge` `expectedFileMtimeMs!!`
  dijamin non-null oleh guard `(size==null) != (mtime==null)` sebelum `matchesIdentity`. ✓
- `MetadataPrescanner`: worker thread, generation guard, `Thread.sleep` hanya di thread
  background. ✓
- `MainActivity`: K5 delete retry via `onActivityResult` + A2 artwork cleanup; cursor
  `.use`; projection per-API; `getSongs` aman. ✓

**C (`native_audio_runtime/src/`):** per-stream state (NAR-4/5) terpakai konsisten,
clamp `nar_dsp_clamp_stream`, fail-open di pipeline, atomics tanpa lock di hot path. ✓

---

## 4. Temuan baru (audit v2)

**Tidak ditemukan bug produksi P1/P2/P3 yang reachable.** Semua area yang dibaca ulang
menunjukkan hardening yang konsisten.

Temuan P4/note baru (murni hygiene dokumen/API, tidak memengaruhi runtime):

| ID | Detail | File |
|---|---|---|
| v2-1 | Doc example `'0.1.0-phase3'` sudah obsolete (runtime actual `phase8.5`) | `lib/services/native/bridges/native_dsp_bridge.dart` (`runtimeVersion` doc) |
| v2-2 | `NativeLoudnessNorm.reset()` (facade) tidak lagi dipanggil produksi — PlaybackManager pakai `resetStream(0)+resetStream(1)`. API dead tapi aman (tetap valid untuk konsumen eksternal) | `native_audio_runtime/lib/src/dsp_pipeline_io.dart` |
| v2-3 | Header comment "Phase 4 additions" di file bindings hand-maintained sudah ketinggalan (file kini mencakup Phase 6–8.5) | `native_audio_runtime/lib/native_audio_runtime_bindings_generated.dart` |
| v2-4 | `AudioOffloadManager.setForceDisabled` retained no-op (didokumentasikan; Media3 1.11 tidak punya API scheduling) | `android/.../audio_offload/AudioOffloadManager.kt` |

Tidak ada perubahan kode yang disarankan untuk v2-1..v2-4 (opsional, kosmetik).

---

## 5. Test gap (tetap)

- Kotlin unit test (ActivePlayerProxyTest, CrossfadeControllerTest, AudioFocusManagerTest,
  dll.) tidak bisa dijalankan tanpa Android SDK.
- `native_audio_runtime/test/` tidak bisa dijalankan dari root (dev-deps nested belum
  di-install); `flutter test` root hanya mencakup 63 test Dart (models/utils/lyrics/widget).
- Tidak ada device test untuk: crossfade audible + volume, bit-perfect toggle, RG di file
  nyata, notifikasi MIUI, RG-2 mtime exFAT.

---

## 6. Kesimpulan

State terbaru app: **bersih dari semua temuan terdokumentasi** (P1/P2/P3/note ter-fix dan
terverifikasi ke source), **`flutter analyze` + 63 test Dart lulus**, dan **tidak ditemukan
bug produksi baru yang reachable** pada re-audit penuh v2 ini. Sisa open hanyalah
keterbatasan yang sudah didokumentasikan (RG-2 mtime granularity device-dependent, N5 dual
cache by design, N6 gating ≤400 ms) plus 4 catatan doc kosmetik (v2-1..v2-4).

Verifikasi final: `flutter analyze` → No issues found · `flutter test` → 63/63 ·
`git diff --check` → bersih (tree bersih, read-only audit).
Kotlin/C tetap perlu kompilasi SDK (`./gradlew :app:compileDebugKotlin`) + device test
untuk konfirmasi runtime.
