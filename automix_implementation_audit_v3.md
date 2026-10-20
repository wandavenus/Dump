# Audit Implementasi AutoMix — v3 (2026-10-20)

**Status:** Audit independen terhadap implementasi AutoMix yang berjalan saat ini. Dokumen v2 (`automix_implementation_audit.md`) diperlakukan sebagai riwayat, bukan sebagai sumber kebenaran; seluruh temuan di bawah ini diverifikasi ulang pada kode HEAD.

**Repository:** `wandavenus/Dump`  
**HEAD yang diaudit:** `c804650cd27fee96fd069b95b9da986ff9af5001`  
**Cakupan:** pipeline Dart (service, engine, cache, settings, library sweep), bridge MethodChannel, decoder/downsampler PCM, JNI, analyzer/planner/live tracker/tone DSP native C, Kotlin dual-player preload/crossfade, NEON, tests, dan CI.  
**Metode:** pembacaan kode statis, penelusuran call-site, pembandingan dokumentasi dengan implementasi, serta eksekusi test lokal.  
**Batasan:** tidak tersedia perangkat Android atau capture PCM pada audit ini. Klaim tentang clipping/true-peak akhir, kualitas fade, dan perilaku akustik di perangkat **belum diverifikasi secara hardware**. Tidak ada perubahan kode yang dilakukan untuk audit ini.

> Catatan eksekusi: working tree hanya berisi perubahan yang sudah ada sebelumnya pada `lib/l10n/app_localizations*.dart` dan `pubspec.lock`. `android/local.properties` dipulihkan ke kondisi semula setelah test Kotlin.

---

## Ringkasan eksekutif

Audit menemukan **3 temuan Tinggi, 4 temuan Sedang, dan 4 temuan Rendah**. Tidak ditemukan crash, data loss, atau pelanggaran memori yang terbukti; suite native lulus di bawah ASan/UBSan. Risiko utama justru ada pada **konsistensi state Dart–native**, **kebenaran exit grid**, dan **klaim proteksi level audio** yang tidak sepenuhnya didukung urutan DSP.

| ID | Severity | Area | Ringkasan | Status |
|---|---|---|---|---|
| AM3-01 | **Tinggi** | Dart merge | Exit BPM/fase dapat diambil dari window middle/head saat tail tidak punya BPM layak | Terbuka |
| AM3-02 | **Tinggi** | Dart → native | Target kosong/same-ID tetap mengaktifkan AutoMix, limiter, tracker, dan durasi fade AutoMix | Terbuka |
| AM3-03 | **Tinggi** | Kotlin abort | Abort mid-fade tidak menghentikan deck lama dan tidak memulihkan volume deck yang dipromosikan | Terbuka |
| AM3-04 | Sedang | Dart engage | Kegagalan `_engageCrossfade` ditelan, tetapi native tetap diaktifkan | Terbuka |
| AM3-05 | Sedang | DSP chain | True-peak limiter berada sebelum `SignalsmithStretch`, sehingga ceiling 0,95 bukan ceiling output akhir | Terbuka |
| AM3-06 | Sedang | CI | Path filter tidak mencakup `crossfade/**`, `Media3PlaybackService.kt`, dan `effects/AutomixToneManager.kt`; tidak ada trigger PR | Terbuka |
| AM3-07 | Sedang | Dokumentasi | Klaim cache v15, planner 23 fitur, centered analyzer 28 nilai, true-peak “not implemented”, gating tracker, dan PR workflow tidak sesuai kode | Terbuka |
| AM3-08 | Rendah | Analisis tail | `tailAnalyzed` ditandai tanpa bukti window mencapai EOF sebenarnya | Terbuka |
| AM3-09 | Rendah | Analisis | Pembulatan `windowSeconds` dan downmix multichannel yang menyertakan LFE | Terbuka |
| AM3-10 | Rendah | Tone manager | `removeProcessor` tidak membersihkan target bass/mid/high | Terbuka |
| AM3-11 | Rendah | Analisis | `windowSeconds` dapat berubah setelah decode head kedua tanpa decode ulang | Terbuka |

**Definisi severity:** *Tinggi* = perilaku audible atau keputusan plan yang salah pada skenario yang wajar, sebaiknya diperbaiki sebelum rilis; *Sedang* = risiko state/coverage/dokumentasi yang dapat menyesatkan atau memperburuk debugging; *Rendah* = edge case/defensif yang dampaknya terbatas.

### Peta cakupan per lapisan

| Lapisan | Berkas utama | Hasil |
|---|---|---|
| Dart planning/cache | `lib/services/automix_service/service.dart`, `engine.dart`, `models.dart`, `plan_signature.dart` | Temuan AM3-01, AM3-02, AM3-04, AM3-08, AM3-11; parsing dan cache identity kuat |
| Kotlin playback | `CrossfadeController.kt`, `Media3PlaybackService.kt`, `AutomixToneManager.kt` | Temuan AM3-02, AM3-03, AM3-05, AM3-10; envelope L1 dan guard utama baik |
| Native C | `automix_analyzer.c`, `automix_planner.c`, `automix_live_tracker.c`, `automix_tone_processor.c`, NEON | Tidak ada bug correctness baru yang terbukti; tracker seqlock/generation dan clamping sampel baik |
| Tests/CI | `test/services/automix_service/`, `android/app/src/test/`, `.github/workflows/` | 113 Dart + 93 Kotlin + suite C lulus; coverage CI punya celah AM3-06 |
| Dokumentasi | `docs/automix-production-wiring.md` | AM3-07 |

---

## Temuan rinci

### AM3-01 — Exit grid dapat diambil dari window middle/head (Tinggi)

**Lokasi:** `lib/services/automix_service/engine.dart:493-531`

**Bukti:** `automixMergeSegments` mengiterasi `segments.reversed` selama `tailSegmentAnalyzed` bernilai true. Jika window tail tidak memiliki `endBpm` dengan confidence ≥ 0,35 dan juga tidak memiliki `bpm` dengan confidence ≥ 0,20, loop **tidak berhenti**; ia lanjut ke window middle, lalu head. Pada cabang pertama, nilai `s.endBpm` dan `s.endBpmConfidence` dari window non-tail dipakai sebagai `tailBpm`/`tailBpmConfidence`, dan `s.startSeconds * 1000 + s.endBeatOffsetMs` dipakai sebagai `tailBeatOffsetMs`.

```dart
// engine.dart:498-515
for (final s
    in tailSegmentAnalyzed
        ? segments.reversed
        : const <AutomixSegmentFeatures>[]) {
  if (s.endBpm != null && s.endBpmConfidence >= 0.35) {
    tailBpm = bpm == null
        ? s.endBpm!
        : automixFoldToOctave(s.endBpm!, bpm);
    tailBpmConfidence = s.endBpmConfidence;
    if (s.endBeatOffsetMs != null && ...) {
      tailBeatOffsetMs =
          s.startSeconds * 1000.0 + s.endBeatOffsetMs!;
    }
    break;
  }
  ...
}
```

Komentar di `engine.dart:376-378` menyatakan “Only tail windows count towards the exit pulse so a missing tail decode cannot silently promote the intro grid to the exit”, tetapi implementasi loop di atas tidak menjaga invariant tersebut ketika tail **berhasil didecode** tetapi tempo tail tidak layak. Cabang kedua juga dapat memakai `s.tailBpmConfidence` dari window middle/head; nilai itu adalah confidence tail dari window tersebut, bukan confidence outro file.

**Dampak:** `tailBpm`/`tailBpmConfidence`/`tailBeatOffsetMs` dapat berasal dari window yang jauh dari akhir lagu. Nilai ini kemudian dipakai oleh `automixHasConfidentTailBpm` (`engine.dart:754-763`), `automixExitBpm` (`:768`), pemilihan `transitionStartMs`/early handover (`:1068-1085`), dan phase lock di native/Kotlin. Selain itu, `endBpm` tetap dihitung dari `segments.last` (`:406-407`), sehingga `endBpm` bisa null sementara `tailBpm` terisi dari middle—dua field exit menjadi tidak konsisten. Akibatnya planner dapat menganggap lagu memiliki exit tempo/fase yang salah, memilih fade duration atau titik handover yang tidak sesuai, dan phase lock mencoba menyelaraskan beat pada fase yang berasal dari tengah lagu.

**Mengapa lolos test:** test `keeps the exit pulse unknown when the tail window failed` (`test/services/automix_service/automix_engine_test.dart:1371`) hanya menguji `tailSegmentAnalyzed: false`. Test `does not substitute general BPM confidence for tail confidence` (`:1417`) menguji tail yang ada tetapi `tailBpmConfidence` nol. Tidak ada test untuk skenario **tail ada, tetapi BPM tail tidak layak, sementara middle/head punya `endBpm` confidence tinggi**.

**Rekomendasi:**
1. Batasi pencarian exit grid hanya ke `segments.last` ketika `tailSegmentAnalyzed` true.
2. Jika tail tidak punya BPM layak, jangan publish `tailBeatOffsetMs`/`tailDownbeatOffsetMs` sama sekali. Fallback ke BPM head boleh untuk sequencing, tetapi dengan confidence 0 dan tanpa fase.
3. Tambahkan regresi tiga window: head confidence tinggi, middle `endBpm` confidence tinggi, tail tanpa BPM → `tailBpm` harus null (atau head BPM dengan confidence 0) dan `tailBeatOffsetMs` null.

---

### AM3-02 — Target kosong/same-ID tetap mengaktifkan AutoMix (Tinggi)

**Lokasi:** `lib/services/automix_service/plan_signature.dart:9-23`, `lib/services/automix_service/service.dart:712-731` dan `:1473-1482`, `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:2379-2395`, `CrossfadeController.kt:538-548`

**Bukti:** `automixImmediateTransitionTargets` sengaja mengembalikan list kosong untuk pasangan same-ID:

```dart
// plan_signature.dart:17-19
if (targets[0]['id'] != null && targets[0]['id'] == targets[1]['id']) {
  return const <Map<String, Object?>>[];
}
```

Komentarnya menyatakan “omit AutoMix-specific cues for that pair and let ordinary crossfade run”. Namun pemanggil tetap menjalankan seluruh jalur AutoMix:

```dart
// service.dart:726-731
await _engageCrossfade(fadeSeconds);
...
await AudioService.setAutomixTransition(
  enabled: true,
  targets: targets,
);
```

Native kemudian menyetel `automixTransitionEnabled = transitionActive` tanpa memeriksa apakah `targets` kosong (`Media3PlaybackService.kt:2384-2385`), mengaktifkan live tracker bila durasi crossfade > 0 (`:2389-2391`), dan mengosongkan semua map target. Di `CrossfadeController.beginCrossfade`, `isAutomixTransitionEnabled()` yang true membuat limiter 0,95 aktif untuk kedua deck (`:542-548`) dan `_engageCrossfade` sudah mengganti durasi crossfade pengguna dengan durasi AutoMix (`service.dart:1557-1562`). Jadi yang berjalan bukan “ordinary crossfade”.

**Dampak:** pada antrean dengan lagu yang sama berurutan (duplikat queue atau queue yang tidak sengaja memuat track sama), pengguna mendapatkan durasi fade AutoMix, tracker PCM aktif, dan limiter per-deck, padahal tidak ada cue AutoMix yang valid. Ini juga membuat state “AutoMix aktif” di Dart/native tidak mencerminkan ada-tidaknya plan yang bisa dipakai.

**Rekomendasi:**
1. Di `_publishPlan` dan `startAutomix`, jika `targets.isEmpty` atau `targets.length < 2`, panggil `setAutomixTransition(enabled: false, targets: [])`, pulihkan crossfade pengguna bila sebelumnya diubah, dan jangan panggil `_engageCrossfade`.
2. Alternatif: buat helper `automixHasUsablePlan(targets)` dan gate seluruh side effect padanya.
3. Tambahkan test di level service, bukan hanya helper: same-ID pair tidak boleh mengubah `crossfadeDuration`, tidak boleh memanggil `setAutomixTransition(enabled: true)`, dan tidak boleh mengaktifkan limiter/tracker. Test helper saat ini hanya ada di `test/services/automix_service/automix_plan_signature_test.dart:152`.

---

### AM3-03 — Abort mid-fade tidak menghentikan deck lama / memulihkan deck yang dipromosikan (Tinggi)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:774-811`; pembanding `cancel()` di `:389-438`; test `CrossfadeControllerTest.kt:329-356`

**Bukti:** cabang abort saat `getActivePlayer() !== newPlayer` melakukan reset gain, flag, preload, queue, dan callback, tetapi **tidak** memanggil `oldPlayer.pause()`, `oldPlayer.stop()`, atau `oldPlayer.clearMediaItems()`. `promotionOwner` justru diset null lebih awal (`:782`), sehingga referensi dari field tersebut hilang sebelum cleanup; parameter lokal `oldPlayer` masih tersedia, tetapi tidak dipakai untuk `stop()`/`clearMediaItems()`. Volume yang dipulihkan hanya volume player aktif saat itu (`:804`); volume `newPlayer` yang tadi naik selama fade tidak dikembalikan.

Sebagai pembanding, `cancel()` secara eksplisit menghentikan dan membersihkan `promotionOwner`:

```kotlin
// CrossfadeController.kt:426-430
promotionOwner?.let { old ->
    try { old.pause()           } catch (_: Exception) {}
    try { old.stop()            } catch (_: Exception) {}
    try { old.clearMediaItems() } catch (_: Exception) {}
}
```

Test C11 (`CrossfadeControllerTest.kt:329-356`) memverifikasi volume player takeover, preload reset, rebuild queue, callback, dan reset tempo, tetapi **tidak** memverifikasi `stop()`/`pause()`/`clearMediaItems()` pada deck lama, dan tidak memverifikasi volume `mockStandbyPlayer` (deck yang dipromosikan). Satu-satunya assertion stop ada di test completion F11 (`:589`), bukan abort.

**Dampak:** pada takeover eksternal di tengah fade, deck lama dapat terus berbunyi bersamaan dengan deck baru (ghost/double audio), dan deck yang dipromosikan dapat tertinggal pada volume parsial. Ini adalah residual dari perbaikan NEW-3 v2: cleanup cancel sudah sebagian besar disalin, tetapi penghentian player dan pemulihan volume kedua deck belum.

**Rekomendasi:**
1. Di cabang abort, hentikan `oldPlayer` dan `newPlayer` bila `newPlayer !== getActivePlayer()`; minimal `pause()` + `stop()` + `clearMediaItems()` pada `oldPlayer`, seperti `cancel()`.
2. Pulihkan volume kedua deck, bukan hanya player aktif.
3. Tambahkan assertion C11 untuk stop/pause/clear dan volume deck yang dipromosikan. Tambahkan juga test untuk takeover yang tidak mengganti `newPlayer` tetapi memindahkan active player ke `oldPlayer`.

---

### AM3-04 — Kegagalan engage ditelan, native tetap diaktifkan (Sedang)

**Lokasi:** `lib/services/automix_service/service.dart:1548-1568`; call-site `:726-731` dan `:1471-1482`; disable `:1524-1545`

**Bukti:** `_engageCrossfade` menangkap semua exception dan hanya mencatat log:

```dart
// service.dart:1562-1568
await AudioEffectsService.setCrossfade(seconds);
if (!_isAutoMixGenerationCurrent(generation)) return;
automixActive.value = true;
} on Object catch (e) {
  LogService.warn('Automix', 'crossfade engage failed: $e');
}
```

Fungsi ini mengembalikan `Future<void>`, sehingga pemanggil tidak tahu apakah engagement berhasil. `_publishPlan` lalu tetap memanggil `setAutomixTransition(enabled: true, targets: targets)` (`:728-731`); `startAutomix` melakukan hal yang sama (`:1479-1482`). Akibatnya `automixActive` bisa tetap false di Dart sementara native sudah memiliki `automixTransitionEnabled = true`, target map terisi, dan limiter/tracker dapat aktif.

**Dampak:** state UI dan state native tidak konsisten. `startAutomix` dapat mengembalikan sukses padahal session tidak benar-benar engaged. `_lastNativeSignature` juga tetap dicatat sebagai plan yang sudah dipublikasikan, sehingga replan berikutnya bisa mengira native sudah memegang plan tersebut. `_disableAutomix` masih membersihkan native dan mencoba restore crossfade dari `_savedCrossfade`, tetapi selama sesi berjalan indikator/status AutoMix bisa salah dan perilaku fade tidak sesuai harapan.

**Rekomendasi:**
1. Ubah `_engageCrossfade` menjadi `Future<bool>` (atau biarkan exception naik).
2. Hanya panggil `setAutomixTransition(enabled: true, ...)` jika engagement berhasil.
3. Jika gagal, panggil `setAutomixTransition(enabled: false, targets: [])`, restore crossfade, dan jangan set `_lastNativeSignature`.
4. Tambahkan test yang memaksa `AudioEffectsService.setCrossfade`/`SharedPreferences` gagal dan memastikan native tidak diaktifkan.

---

### AM3-05 — True-peak limiter berada sebelum `SignalsmithStretch` (Sedang)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:1500-1504`; limiter `CrossfadeController.kt:538-548`; implementasi native `native_audio_runtime/src/automix_tone_processor.c:131-140`; klaim dokumen `docs/automix-production-wiring.md:79,89`

**Bukti:** urutan chain produksi adalah:

```kotlin
// Media3PlaybackService.kt:1503
toFloatProc, nativeDspProc, channelMixingProc, reverbProc,
automixToneProc, stretchProc, toInt16Proc
```

True-peak limiter berada di dalam `AutomixToneAudioProcessor`, yaitu **sebelum** `stretchProc`. Limiter membatasi estimasi true peak pada tahap tone, lalu `SignalsmithStretch` melakukan time-stretch/pitch-shift dan dapat menghasilkan overshoot atau inter-sample peak baru. `toInt16Proc` setelahnya hanya melakukan clamp sample PCM 16-bit, bukan true-peak limiting. `player.volume` Kotlin juga diterapkan setelah chain.

**Dampak:** ceiling 0,95 yang diklaim untuk output per-deck tidak menjamin output setelah Stretch. Pada materi dengan transient kuat atau saat stretch aktif, peak akhir dapat melewati ceiling. Ini adalah risiko kualitas audio/clipping, bukan crash. Karena tidak ada capture PCM perangkat, besaran aktualnya belum terukur.

**Rekomendasi:**
1. Pindahkan limiter ke tahap setelah `SignalsmithStretch` (processor terpisah atau stage akhir di `StretchAwareAudioProcessorChain`), atau tambahkan limiter kedua setelah Stretch.
2. Jika keputusan produk adalah mempertahankan limiter pra-Stretch, ubah dokumentasi menjadi “pre-stretch per-deck limiter” dan jangan klaim output akhir ≤ 0,95.
3. Tambahkan regression test urutan chain (bukan hanya unit test limiter native) dan test sinyal transient setelah stretch bila memungkinkan.

---

### AM3-06 — CI tidak mencakup berkas playback AutoMix yang paling berisiko (Sedang)

**Lokasi:** `.github/workflows/run-noisegraph-tests.yml:3-20` dan `:82-83`; `.github/workflows/ci.yml:3-4`; `.github/workflows/kotlin-tests.yml:3-4`; `.github/workflows/flutter-check.yml:3-4`

**Bukti:** path filter `run-noisegraph-tests.yml` mencakup `android/app/src/main/kotlin/dev/wndavenz/music/automix/**`, tetapi **tidak** mencakup:
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/**` dan `android/app/src/test/kotlin/dev/wndavenz/music/crossfade/**` (tempat `CrossfadeController.kt` dan test C11 berada),
- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt` (tempat target map, tracker gating, dan urutan chain),
- `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixToneManager.kt` (tempat limiter dan band gain).

Workflow ini hanya memiliki trigger `push` ke `main` dan `workflow_dispatch`; tidak ada `pull_request`. Job `android-build-validation` memiliki kondisi `github.event_name == 'pull_request'` (`:83`), tetapi karena workflow tidak pernah dipicu oleh PR, kondisi itu tidak pernah benar. `ci.yml`, `kotlin-tests.yml`, dan `flutter-check.yml` seluruhnya `workflow_dispatch` saja.

**Dampak:** perubahan pada fade/abort/limiter—termasuk perbaikan untuk temuan di laporan ini—tidak otomatis menjalankan suite AutoMix. Regresi dapat masuk tanpa sinyal CI, dan hasil `run-noisegraph-tests` hanya valid untuk SHA yang memicu push ke `main` atau dispatch manual.

**Rekomendasi:**
1. Tambahkan path `crossfade/**`, `Media3PlaybackService.kt`, dan `effects/AutomixToneManager.kt` ke filter.
2. Tambahkan trigger `pull_request` yang relevan, atau hapus kondisi `pull_request` yang mati.
3. Pertimbangkan menjalankan focused Kotlin AutoMix suites pada PR, bukan hanya full dispatch.

---

### AM3-07 — Dokumentasi tidak sesuai implementasi (Sedang, dokumentasi)

**Lokasi:** `docs/automix-production-wiring.md`

**Bukti:**

| Klaim dokumen | Implementasi aktual | Bukti |
|---|---|---|
| Cache schema **v15** (`docs:11`) | **v16** | `lib/services/automix_service/service.dart:1006` |
| Planner menerima **23** feature per track (`docs:32`) | **27** | `native_audio_runtime/src/automix_native.h:13`; `native_audio_runtime/lib/src/automix_native_io.dart:9` |
| `nar_automix_analyze_centered` mengembalikan **28-value** contract (`docs:8`) | **32** nilai; paragraf yang sama juga menyebut 32 | `native_audio_runtime/src/automix_native.h:15`; `automix_native_io.dart:8` |
| True-peak limiting **not implemented** (`docs:102`) | Diimplementasikan sebagai limiter per-deck di §4 dan di kode | `docs:79,89,92`; `automix_tone_processor.c:131-140` |
| Live tracker hanya aktif bila planner punya beat grid valid untuk kedua track (`docs:73`) | Tracker aktif bila `transitionActive && crossfadeDurationSec > 0`; gating beat-grid baru dilakukan untuk phase lock, bukan untuk tracker | `Media3PlaybackService.kt:2389-2391`; `CrossfadeController.kt:561-565` |
| Ada PR verification workflow (`docs:98`) | Di repo ini tidak ada workflow dengan trigger PR; workflow yang ada `workflow_dispatch`/push main | `.github/workflows/ci.yml:3-4`; `run-noisegraph-tests.yml:3-20` |

**Dampak:** pembaca—terutama reviewer keamanan audio—dapat menganggap ceiling true-peak sudah menjamin output akhir, padahal limiter berada sebelum Stretch. Kontradiksi “not implemented” vs §4 juga membuat status fitur tidak dapat dipercaya. Angka cache/feature yang salah menyulitkan audit berikutnya.

**Rekomendasi:** perbarui dokumen mengikuti kode saat ini; untuk true-peak, jelaskan posisi limiter dan batasannya. Jika AM3-05 diperbaiki dengan memindahkan limiter, perbarui §4 dan §6 sekaligus.

---

### AM3-08 — `tailAnalyzed` ditandai tanpa bukti mencapai EOF (Rendah)

**Lokasi:** `lib/services/automix_service/service.dart:1758-1770`; `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt:119-126`

**Bukti:** bridge menganggap window berhasil jika `decoded` true **atau** `reachedCap` true, dengan syarat minimal 1 detik audio:

```kotlin
// AutomixAnalysisBridge.kt:124-126
val reachedCap = collected.size.toLong() >= analysisRate.toLong() * windowSeconds
if (!decoded && !reachedCap) return null
if (collected.size < analysisRate) return null
```

Untuk tail window, `reachedCap` hanya membuktikan buffer sepanjang `windowSeconds` penuh—bukan bahwa posisi tersebut adalah EOF file sebenarnya. `_analyzeSegments` menandai `tailAnalyzed = true` untuk setiap hasil tail non-null (`service.dart:1766-1769`) tanpa memeriksa apakah `segment.startSeconds + segment.seconds` mencapai `fileSeconds`. Jika `MediaFormat.KEY_DURATION` lebih pendek dari durasi file sebenarnya, tail window berhenti di durasi nominal dan metadata “tail” sebenarnya berasal dari tengah file; metadata itu tetap dipersist sebagai `tailAnalyzed` (`models.dart:542`).

**Catatan koreksi:** klaim bahwa cache parsial tidak pernah di-retry **tidak terbukti**. `_analyzeOneUncached` memang me-retry entri dengan `tailAnalyzed == false` (`service.dart:1849-1859`). Yang bermasalah adalah `tailAnalyzed == true` yang dapat diset terlalu awal, bukan retry cache parsial.

**Dampak:** rendah karena durasi container biasanya akurat; namun pada file dengan durasi metadata stale/lebih pendek, exit grid dan outro energy dapat berasal dari window yang bukan outro. Sulit terdeteksi karena fitur tampak “lengkap”.

**Rekomendasi:** kembalikan `reachedEof`/`decodedSeconds` dari bridge; di merge, tandai tail analyzed hanya jika window mencakup akhir durasi yang diresolusi (dengan toleransi kecil). Jika tidak, perlakukan sebagai partial dan retry.

---

### AM3-09 — Pembulatan window dan LFE pada downmix multichannel (Rendah)

**Lokasi:** `AutomixAnalysisBridge.kt:63-66`; `AutomixPcmDownsampler.kt:83-121`

**Bukti:**
- `windowSeconds = safeMaxSeconds.coerceIn(...).toInt()` memotong bagian pecahan. Window produksi saat ini hampir selalu integral (60/120 detik), sehingga dampaknya kecil, tetapi pemanggil baru atau durasi pecahan dapat menganalisis window lebih pendek dari yang diminta.
- Downmix multichannel mengiterasi **semua** channel dan memberi bobot berbasis RMS tanpa mengecualikan LFE:

```kotlin
// AutomixPcmDownsampler.kt:87-95
for (ch in 0 until channels) {
    val sample = interleavedPcm16[base + ch] / 32768.0
    ...
    channelPower[ch] += channelPowerSmoothing * (power - channelPower[ch])
```

Pada layout standar 5.1/7.1, channel index 3 umumnya LFE. LFE dapat mendominasi energi rendah dan memengaruhi BPM/key/onset analysis.

**Dampak:** akurasi analisis pada file surround dan window pecahan; tidak memengaruhi playback stereo normal secara langsung. Tidak ada channel mask yang tersedia di `PcmDecoder.TrackFormat`, sehingga identifikasi LFE saat ini tidak mungkin dilakukan secara pasti tanpa perubahan API.

**Rekomendasi:** gunakan `roundToInt()`/`ceilToInt()` untuk window; bila channel mask tersedia, kecualikan atau attenuate LFE sebelum downmix. Tambahkan test 5.1 dengan konten LFE dominan.

---

### AM3-10 — `removeProcessor` meninggalkan target band gain (Rendah)

**Lokasi:** `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixToneManager.kt:259-272`; pembuatan processor `:239-255`

**Bukti:** `removeProcessor` menghapus entry `processors` dan `targetTruePeakCeilings`, lalu mereset native fade/true-peak untuk slot. Namun `targetGains`, `targetMidGains`, dan `targetHighGains` tidak dihapus atau direset. Jika processor baru dibuat untuk slot yang sama sebelum `reset()` dipanggil, `createProcessor` akan membaca nilai lama (`:247-250`) dan menerapkannya ke processor baru (`:252-255`).

**Dampak:** rendah karena `applyAutomixTransitionNow` memanggil `automixToneManager.reset()` pada setiap update target, dan reset menetapkan gain ke 1. Namun removal di luar alur reset dapat mewariskan EQ lama ke processor berikutnya.

**Rekomendasi:** hapus ketiga map untuk slot tersebut di `removeProcessor`, atau set ke 1f; tambahkan test create → set gain → remove → create.

---

### AM3-11 — `windowSeconds` dapat berubah setelah decode head kedua tanpa decode ulang (Rendah)

**Lokasi:** `lib/services/automix_service/service.dart:1741-1757`

**Bukti:** setelah head didecode ulang karena durasi decoder berbeda, kode menghitung `windowSeconds = analysisWindowSecondsForDuration(fileSeconds)` sekali lagi (`:1750`), tetapi tidak men-decode ulang head bila nilai itu berubah. Head yang tersimpan masih berasal dari window lama, sedangkan tail dan middle memakai `windowSeconds` baru. Ini dapat menghasilkan overlap atau gap antara head dan tail.

**Dampak:** rendah karena durasi decoder biasanya stabil setelah pembacaan pertama; namun pada container dengan durasi tidak konsisten, window bisa tumpang tindih atau meninggalkan celah yang tidak dianalisis.

**Rekomendasi:** ulangi loop sampai `windowSeconds` stabil (dengan batas iterasi), atau decode ulang head ketika nilai berubah. Tambahkan test dengan durasi head yang berubah antar decode.

---

## Hal yang terverifikasi baik

1. **Parsing dan validasi fitur ketat.** `automixSegmentFeaturesFromAnalysisMap` memvalidasi tipe, finite value, rentang confidence, Camelot, dan offset; nilai rusak menjadi fallback netral, bukan exception. Cache memeriksa versi schema dan identitas file (size + mtime) sebelum dipakai (`service.dart:1006`, `:1200-1235`).
2. **Planner Dart dan native konsisten.** `NAR_AUTOMIX_FEATURE_COUNT = 27` dan `_featureCount = 27`; test parity native/reference mencakup beberapa profile dan fixture 25+ track.
3. **Live tracker concurrency baik.** Publikasi memakai seqlock dengan `atomic_flag` try-lock dan generation per slot (`automix_live_tracker.c:55-157`); audio callback tidak memblokir. Ini menghindari torn read tuple BPM/fase/confidence.
4. **Envelope fade Kotlin dan L1 budget baik.** `AutomixGainEnvelope` membatasi jumlah koefisien kedua deck; test C/F memverifikasi budget dan arah kurva. Catatan: ini bukan jaminan post-mix.
5. **Clamping sampel native/NEON baik.** Jalur scalar dan NEON meng-clamp sampel ke `[-1, 1]`; suite C memverifikasi over-range dan block-boundary continuity.
6. **Cleanup abort sudah jauh lebih baik dari v2.** Volume player takeover, preload index, queue satu-item, dan callback sudah dipulihkan; residual-nya adalah AM3-03 (stop deck lama dan volume deck promosi).
7. **Test suite luas.** 113 test Dart, 93 test Kotlin (7 suite), dan suite C native lulus di bawah ASan/UBSan.

---

## Hasil pengujian lokal

| Pemeriksaan | Perintah | Hasil |
|---|---|---|
| Dart analyzer | `flutter analyze --no-pub` | **No issues found** |
| Dart AutoMix tests | `flutter test test/services/automix_service --no-pub` | **113/113 lulus** |
| Kotlin AutoMix/crossfade tests | `:app:testDebugUnitTest` dengan filter `dev.wndavenz.music.automix.*` dan `dev.wndavenz.music.crossfade.*` | **93/93 lulus** (8 + 10 + 6 + 4 + 8 + 16 + 41) |
| Native C suite | GCC `-fsanitize=address,undefined`, seluruh sumber `automix_*` | **exit 0** (ASan/UBSan; leak detection dimatikan) |

**Catatan eksekusi:**
- Untuk test Flutter dengan native asset, `/usr/lib/ccache` dihapus sementara dari `PATH`.
- Test Kotlin memakai `GRADLE_USER_HOME=/tmp/opencode/gradle` dan mapping SDK sementara; `android/local.properties` dipulihkan ke `sdk.dir=/opt/android-sdk`.
- Suite C dijalankan pada x86_64. Jalur NEON ARM64 tidak dieksekusi secara lokal; klaim NEON hanya didasarkan pada review kode dan test suite yang ada.
- Tidak ada device/emulator audio capture, sehingga temuan AM3-05 dan klaim kualitas fade belum terukur di hardware.

---

## Kesimpulan

Secara arsitektur, AutoMix sudah cukup matang: pemisahan planner Dart/native, validasi fitur, cache identity, envelope fade L1, tracker seqlock, dan suite test menunjukkan engineering yang serius. Namun tiga jalur masih dapat menghasilkan perilaku yang tidak sesuai kontrak: **exit grid yang diambil dari window salah**, **AutoMix yang tetap armed tanpa target valid**, dan **abort yang tidak sepenuhnya membersihkan kedua deck**. Ditambah limiter true-peak yang berada sebelum Stretch, klaim keamanan level audio saat ini lebih kuat daripada yang benar-benar dijamin oleh urutan DSP. Perbaikan tiga temuan Tinggi dan penyelarasan dokumentasi/CI sebaiknya diprioritaskan sebelum menganggap AutoMix siap untuk validasi audio di perangkat.

## Prioritas perbaikan

1. **AM3-01** — batasi exit grid ke tail window; ini memperbaiki kebenaran planner dan phase lock.
2. **AM3-02** — jangan aktifkan AutoMix untuk target kosong/same-ID; ini mengembalikan janji “ordinary crossfade”.
3. **AM3-03** — lengkapi abort cleanup seperti `cancel()`; ini mencegah ghost audio setelah takeover.
4. **AM3-04** — propagasikan kegagalan engage sebelum mengaktifkan native.
5. **AM3-05** — pindahkan/duplikasi limiter setelah Stretch, atau koreksi klaim dokumentasi.
6. **AM3-06/07** — perbaiki trigger CI dan sinkronkan dokumentasi.
7. **AM3-08 s.d. AM3-11** — perbaikan defensif dan akurasi analisis.

---

## Lampiran — batasan audit

- Audit ini tidak melakukan profiling CPU, pengukuran latency, atau listening test.
- Tidak ada verifikasi terhadap output PCM gabungan dua deck di AudioFlinger.
- Tidak ada verifikasi terhadap perilaku codec tertentu (ALAC/FFmpeg, multichannel eksotis) di perangkat.
- Kesimpulan “tinggi/sedang/rendah” menggabungkan dampak audio/UX, kemungkinan terjadinya, dan cakupan test; bukan skor CVSS.
- Dokumen v2 tetap disimpan sebagai riwayat. Laporan ini tidak menggantikan test runtime perangkat yang belum tersedia.
