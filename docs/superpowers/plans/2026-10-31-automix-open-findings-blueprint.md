# AutoMix Open Findings — Blueprint Eksekusi

> **Status:** dokumen perencanaan. Tidak ada perubahan perilaku pada pembuatannya.
> **Basis:** commit `d27de4c`, aplikasi `v1.5.66`, cache schema **v23**, ABI analyzer **45**.
> **Cakupan:** temuan terbuka audit AutoMix v9 dan sisa Fase 5–6. Audit repo lain (UI/UX, keamanan, log) tidak termasuk.
> **Target perangkat:** Xiaomi Mi 9T / Redmi K20, arm64-v8a, Android 11 / MIUI 12. Jangan menambah jalur kompatibilitas perangkat/ABI lain.

Dokumen ini dibuat agar agent berikutnya dapat mengambil satu workstream tanpa menebak urutan, file, atau definisi selesai. Kerjakan **satu PR kecil per item**; jangan menggabungkan perubahan ABI, algoritma, dan cleanup dalam satu PR.

---

## 1. Aturan eksekusi wajib

1. Baca `AGENTS.md`, `docs/ARCHITECTURE.md`, `.agents/memory/automix-fase3-6-v23.md`, dan `docs/automix-production-wiring.md` sebelum menyentuh kode.
2. Jangan mengulang implementasi dasar yang sudah ada (daftar di §2.1); residual parsialnya ada di §2.2.
3. Setiap perubahan perilaku wajib:
   - menaikkan `version:` di `pubspec.yaml` ke versi baru (jangan memakai ulang `1.5.66`);
   - menambah entri **paling atas** di `lib/pages/settings_page/changelog_data.dart` dengan versi yang sama;
   - memperbarui `docs/automix-production-wiring.md` bila kontrak/ABI/cache berubah;
   - memperbarui `.agents/memory/automix-fase3-6-v23.md` (atau memory pengganti) dan index `MEMORY.md` di akhir sesi.
4. Perubahan kontrak analyzer wajib memperbarui **lima tempat** secara sinkron:
   - `native_audio_runtime/src/automix_native.h` (konstanta dan dokumentasi slot);
   - `native_audio_runtime/src/automix_analyzer.c` (output aktual);
   - `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixAnalysisBridge.kt` dan `AutomixNative.kt` (map JNI/Kotlin);
   - `native_audio_runtime/lib/src/automix_native_io.dart` dan `automix_native_types.dart` (FFI Dart);
   - parser `lib/services/automix_service/models.dart` serta tes ABI.
5. Setiap perubahan skema cache wajib menaikkan `_analysisSchemaVersion` di `lib/services/automix_service/service.dart`, memperbarui fixture/tes, dan memastikan entri lama menjadi cache miss yang aman.
6. File C baru wajib didaftarkan di `native_audio_runtime/hook/build.dart` (sumber build native, bukan Gradle). Modul JNI Android tetap mengikuti `android/app/src/main/cpp/CMakeLists.txt`. Audio thread tidak boleh alokasi, logging, atau mengambil lock.
7. Jangan mengubah `output[3]` (beat phase) ke DP tanpa memperbarui golden dan memeriksa pergeseran timestamp frame. Golden lama adalah kontrak regresi.
8. Untuk API pihak ketiga (Media3 1.11.1 dan lainnya), cek dokumentasi resmi via Context7 dan cocokkan dengan versi di repo sebelum coding.
9. Jangan build APK di environment ini. Jangan menjalankan `flutter build apk` atau variannya.
10. Tes Flutter di workspace ini memakai `TMPDIR=/dev/shm`; suite native memakai `-j 1`. Jangan mengklaim tes lulus jika perintah tidak benar-benar dijalankan.
11. Stage hanya file untuk request aktif. Jangan commit/push/reset/clean tanpa permintaan eksplisit.

### Perintah verifikasi dasar

```bash
flutter pub get
dart analyze lib test
TMPDIR=/dev/shm flutter test test/services/automix_service
(cd native_audio_runtime && dart test -j 1)
dart run tools/automix_bench.dart --check
```

C suite (dari root):

```bash
cd native_audio_runtime && clang -std=c11 -O1 -g -Isrc -Itest \
  test/automix_native_c_test.c \
  src/automix_analyzer.c src/automix_planner.c \
  src/automix_live_tracker.c src/automix_phase_lock.c \
  src/automix_tone_processor.c -lm -lpthread \
  -o /tmp/automix_native_c_test && /tmp/automix_native_c_test
```

Kotlin, setelah environment punya disk + JDK 21 + Android SDK 36 + NDK 28.2.13676358 + CMake 3.22.1:

```bash
cd android && ./gradlew :app:testDebugUnitTest \
  --tests "dev.wndavenz.music.automix.AutomixTransitionPolicyTest"
```

Audio regression (butuh `ffmpeg`, `ffprobe`, Java):

```bash
tools/automix_ffmpeg_regression.sh
```

---

## 2. Peta status

### 2.1 Sudah ada mekanismenya — jangan mengulang implementasi dasar

| ID | Perubahan yang sudah ada |
|---|---|
| H02 | Cache file per lagu, decode isolate, migrasi legacy, prune, prefix 20 + hysteresis |
| H03 | Artist cooldown masuk `transition_cost`, `link_cost`, `path_cost`, dan beam |
| H04 | Top-3 drop cue per window; envelope 8–150 s; early handover phrase snap |
| H05 | Label struktur seam Dart dinormalisasi terhadap window; fallback native tetap ada |
| M01 | Cue drop/breakdown snap ke `metre × 4` |
| M07 | Rencana dibatasi prefix 20; minimal 4 decoded; hysteresis 5% |
| M10 | Edge RMS/LUFS/onset 15 s sudah dipakai untuk trim dan strategi |
| M11 | Atenuasi mid vokal kontinu, bukan 0,78 tetap |
| M12 | Beam search width 8/depth 2 di C dan mirror Dart |
| M13 | Durasi short/quick/long dalam bar, lalu clamp 1,5–12 s |
| M15 | Early handover boleh snap satu frasa penuh |
| M16 | Prune cache dan migrasi file |
| M18 | Kontrak BPM 50–220 disatukan di header C lalu Dart/Kotlin |

**Catatan:** tabel ini hanya berarti mekanisme dasarnya sudah ada. H05/M10/M11 masih punya residual yang tercantum di §2.2; validasi H01/H05/M10/M11 tetap ada di §10. Jangan menghapus mekanisme yang sudah ada saat mengerjakan residual.

### 2.2 Matriks temuan yang masih terbuka

| ID | Temuan | Status | Workstream | Dependency | Risiko |
|---|---|---|---|---|---|
| M17 | Suite native tidak parallel-safe; perintah dokumentasi masih `dart test` | Open | WS0 | — | Rendah |
| L01 | Estimasi kuartal tempo dihitung ulang beberapa kali | Open | WS1 | — | Rendah |
| L02 | Guard ring buffer live tracker di tepi window | Open | WS1 | — | Rendah |
| L04 | `median_float` malloc/copy/qsort setiap panggilan | Open | WS1 | — | Rendah |
| L05 | Clamp LUFS fallback −24…−6 membuat ambient terlalu keras | Open | WS1 | — | Rendah |
| M14 | Jalur native per-sample fade dormant (`nativeFadeAvailable = false`) | Open | WS1 | — | Rendah |
| M05 | Anti-fase stereo per sampel + filter anti-alias 2-pole | Open | WS2 | Cache bump | Sedang |
| L06 | File >10 menit hanya 5 window; ada gap yang tidak dianalisis | Open | WS2 | — | Sedang |
| M10 | Belum ada short-term LUFS untuk overlap | Open/parsial | WS2 | ABI + cache | Sedang |
| H01r | Ambang strategi/trim dari fitur edge belum dikalibrasi; belum ada A/B audio | Partial | WS6 | Corpus/audio | Sedang |
| H05r | Label native fallback masih berbasis ambang absolut; ambang struktur belum dikalibrasi | Partial | WS2/WS6 | Corpus | Rendah–sedang |
| M03 | Key global per window, belum seam key; HPCP 2 harmonik | Open | WS3 | Corpus untuk validasi | Tinggi |
| M09 | Chord Viterbi root-only; kualitas greedy; penalti lemah | Open | WS3 | Corpus untuk validasi | Sedang |
| M06 | Biaya analisis/WCET belum diukur; STFT chord terpisah | Open | WS3 | Profiling | Sedang |
| M04 | Belum ada tempo map/beat tracking per bar | Open/parsial | WS4 | Corpus + golden | Tinggi |
| Fase 5 | Downbeat HMM/bar-level, phrase SSM | Open | WS4 | M04 + corpus | Tinggi |
| M02 | Belum ada tempo arc dan biaya lompatan oktaf eksplisit | Open | WS4 | — | Sedang |
| M08 | Confidence belum dikalibrasi; ambang tersebar | Open | WS1/WS4 | Corpus | Sedang |
| M11 | LR4 crossover dan adaptive ducking belum ada | Open/parsial | WS5 | Device capture | Sedang |
| P09 | Post-mix true-peak limiter belum ada; butuh shared mix bus | Keputusan | WS5 | Spike arsitektur | Tinggi |
| P01–P10 | Hipotesis akurasi/audio/UX belum diuji | Validasi | WS6 | Corpus/perangkat | Sedang–tinggi |

---

## 3. Urutan PR yang disarankan

| PR | Isi | Alasan urutan |
|---|---|---|
| **PR-0** | M17 + baseline report + korpus manifest | Menutup ketidakpastian harness sebelum menyentuh algoritma |
| **PR-1** | L01, L02, L04, L05 | Perbaikan kecil, tanpa perubahan ABI/golden |
| **PR-2** | M14 (hapus jalur dormant) | Mengurangi dead code sebelum pekerjaan audio besar |
| **PR-3** | M05 + tes sinyal anti-fase + cache bump | Perbaikan input analyzer; harus sebelum evaluasi akurasi |
| **PR-4** | L06 + M10 + ABI append + cache bump | Perluasan coverage dan fitur seam; satu jalur ABI |
| **PR-5** | M03 seam key + cache bump | Perubahan harmonik terisolasi |
| **PR-6** | M09 chord HMM + cache bump | Perubahan chord terisolasi |
| **PR-7** | M04 tempo map + downbeat/phrase | Perubahan grid; risiko golden |
| **PR-8** | M02 tempo arc + planner parity | Planner dapat memakai tempo yang sudah lebih stabil |
| **PR-9** | M11 LR4; ducking opsional | Perubahan DSP real-time; setelah metrik analyzer stabil |
| **PR-10** | P09 spike/decision, lalu implementasi bila disetujui | Arsitektur audio; jangan dicampur dengan PR lain |
| **PR-11** | M08 kalibrasi + P01/P08 corpus | Kalibrasi butuh data, bukan tebakan |

Jika waktu terbatas, urutan dampak terbaik: **PR-0 → PR-1 → PR-3 → PR-4 → PR-8 → PR-7**. M03/M09/P09 boleh berjalan paralel sebagai riset, tetapi jangan merge tanpa data validasi.

---

## 4. WS0 — Baseline, harness, dan data

### 4.1 M17 — Jadikan suite native deterministik

**Masalah:** `dart test` default menjalankan beberapa berkas paralel dan berbagi state global C (`g_states`, `g_tracker`, `g_published`), sehingga 64 tes bisa gagal meski tiap berkas lulus sendiri.

**Langkah:**
1. Reproduksi:
   ```bash
   cd native_audio_runtime
   dart test
   dart test -j 1
   ```
2. Pilih satu solusi, jangan dua-duanya:
   - **A (disarankan):** tambahkan konfigurasi tes yang memaksa `concurrency: 1` dan ubah perintah di `AGENTS.md`/CI; atau
   - **B:** tambahkan `reset` global eksplisit di `setUp` untuk tone/tracker/pipeline dan tetap jalankan per-file jika state masih bocor.
3. Verifikasi bahwa `dart test` tanpa flag tambahan lulus di checkout bersih.
4. Jangan mengubah kode produksi hanya untuk membuat tes paralel; state global adalah desain audio.

**Selesai bila:** perintah yang didokumentasikan lulus konsisten, dan CI memakai perintah yang sama.

### 4.2 Baseline Kotlin, ffmpeg, dan benchmark

Jalankan di environment dengan disk cukup. Catat commit, versi JDK/SDK/NDK, hasil per kelas, dan error lingkungan secara terpisah dari kegagalan assertion.

```bash
cd android && ./gradlew :app:testDebugUnitTest \
  --tests "dev.wndavenz.music.automix.AutomixTransitionPolicyTest"
```

Lalu, bila memungkinkan, seluruh `:app:testDebugUnitTest`. Jalankan juga `tools/automix_ffmpeg_regression.sh` dan `dart run tools/automix_bench.dart --check`.

**Output:** laporan baseline (disarankan `docs/automix-validation-baseline.md`) berisi:
- perintah persis yang dijalankan;
- jumlah lulus/gagal;
- nama tes yang gagal dan apakah karena lingkungan;
- hasil golden BPM/metre/key;
- catatan bahwa APK tidak dibangun.

### 4.3 Korpus dan manifest

Tanpa corpus, P01/P08/M08 tidak bisa ditutup. Siapkan `testdata/automix/` dengan manifest JSON:

```json
{
  "path": "relative/or/hash-only.wav",
  "genre": "house",
  "bpm": 124.0,
  "meter": 4,
  "key": "8A",
  "beats": [],
  "downbeats": [],
  "phrases": [],
  "sections": [],
  "mixPoints": []
}
```

Aturan:
- Jangan commit audio berhak cipta. Gunakan sinyal sintetis, sampel berlisensi, atau path yang di-resolve di luar repo.
- Target audit: 120 track, minimal subset 4/4 30 track untuk F1 beat/downbeat.
- Label BPM harus diverifikasi manual/aubio/madmom, bukan hanya output analyzer.
- Untuk key/chord, gunakan label manual atau Mixed In Key; simpan confidence sumber.

**Selesai bila:** manifest dapat dibaca `tools/automix_bench.dart`, subset 10 track berjalan <2 menit, dan label tidak diedit otomatis oleh analyzer.

---

## 5. WS1 — Perbaikan kecil dan observability

### 5.1 L02 — Guard ring buffer live tracker

**File:** `native_audio_runtime/src/automix_live_tracker.c`.

**Perubahan:** sebelum memakai `previous_age = age + phase_lag` atau `history_age`, pastikan indeks berada di `[0, history_count)`. Kembalikan nol/netral bila di luar. Jangan mengubah algoritma phase scoring.

**Tes:** tambah kasus di C suite dengan history belum penuh dan `phase_lag` besar; pastikan tidak membaca sampel stale dan output phase tetap finite.

### 5.2 L04 — Scratch buffer untuk median

**File:** `native_audio_runtime/src/automix_analyzer.c` (`median_float`).

**Perubahan:** alokasikan buffer scratch sekali per analisis (atau gunakan buffer stack berukuran tetap), lalu isi/salin dan urutkan tanpa `malloc` berulang. Jangan mengubah nilai median. Jika ukuran dinamis tidak aman, pertahankan fallback alokasi dan catat batasnya.

**Tes:** nilai median identik untuk array genap/ganjil dan data dengan NaN; tidak ada kebocoran.

### 5.3 L05 — Clamp LUFS fallback

**File:** `lib/services/automix_service/service.dart` (fallback `lufs = (-18.0 - loudness.gainDb).clamp(-24, -6)`).

**Perubahan:** perluas batas bawah atau gunakan RMS edge saat LUFS tidak tersedia, agar track ambient tidak dipetakan ke −24. Jangan mengubah track yang punya LUFS valid.

**Tes:** unit test track sangat sunyi; energi/trim tidak melonjak; fallback tetap finite.

### 5.4 L01 — Hindari estimasi kuartal berulang

**File:** `native_audio_runtime/src/automix_analyzer.c` (`estimate_tempo`, loop tempo curve, fallback ODF).

**Perubahan:** kembalikan hasil empat kuartal dari satu pass melalui struct; pakai hasil itu untuk konsensus, kurva, dan stability. Jangan mengubah urutan window atau nilai output.

**Tes:** golden analyzer harus identik (atau perbedaan dijelaskan sebagai bugfix); bandingkan output sebelum/sesudah untuk sinyal 120 BPM dan drift.

### 5.5 M14 — Putuskan jalur native fade

**File:** `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt`, `Media3PlaybackService.kt`, `native_audio_runtime/src/automix_tone_processor.c`, tes native/Kotlin, docs.

**Rekomendasi:** hapus jalur `nativeFadeAvailable` dan `setAutoMixCrossfadeGains` dari produksi karena jalur ini bukan shared post-mix bus dan tidak memberi keuntungan pada arsitektur dual-AudioTrack saat ini. Jalur Kotlin `AutomixGainEnvelope` adalah satu-satunya envelope produksi. Jangan menghapus tone processor/true-peak limiter per-deck.

**Jika memilih mengaktifkan:** jangan flip boolean. Buat spike terpisah dengan shared fade epoch, uji dua AudioTrack, dan capture perangkat. Itu bukan pekerjaan PR kecil, dan tidak menyelesaikan P09.

**Selesai bila:** tidak ada referensi dead path yang membingungkan, docs menyatakan jalur produksi dengan benar, dan tes yang relevan tetap lulus.

### 5.6 M08a — Inventaris ambang, belum kalibrasi

**File:** `native_audio_runtime/src/automix_native.h`, `AutomixContract.kt`, `lib/services/automix_service/contract.dart`, `docs/automix-production-wiring.md`.

**Perubahan:** buat satu tabel ambang (tempo/key/drop/vocal/structure) dan tes yang memastikan C/Dart/Kotlin memakai nilai yang sama. Jangan mengubah nilai tanpa corpus. Ini menutup bagian “ambang tersebar”; kalibrasi probabilistik tetap M08b di WS4.

---

## 6. WS2 — Input analyzer dan seam

### 6.1 M05 — Downsampler stereo dan anti-alias

**File:** `android/app/src/main/kotlin/dev/wndavenz/music/automix/AutomixPcmDownsampler.kt`, `AutomixPcmDownsamplerTest.kt`.

**Perubahan yang diminta:**
1. Ganti keputusan per sampel `|mid| < 0.25 * max(|L|,|R|)` dengan keputusan berbasis energi mid/side yang dihaluskan minimal ~20 ms. Pertahankan fallback mono untuk kanal identik.
2. Naikkan filter anti-alias menjadi 4th-order Butterworth pada cutoff ~0.40 × `fs_out`, atau FIR linear-phase ~63 tap. Jangan sekaligus mengganti decimasi ke polyphase kecuali benchmark menunjukkan butuh.
3. Jangan mengubah laju output atau kontrak sample rate tanpa memperbarui bridge dan cache.

**Tes wajib:**
- sinyal anti-fase (L = −R) tidak menghasilkan kanal yang berkedip;
- pad wide/stereo widening menghasilkan onset/chroma yang stabil;
- nada 12–24 kHz tidak alias ke pita chroma;
- BPM/key fixture sebelum/sesudah dibandingkan dan perubahannya dijelaskan;
- cache schema dinaikkan karena fitur dapat berubah.

### 6.2 L06 — Coverage file panjang

**File:** `AutomixAnalysisBridge.kt` (`planWindowStarts`, `planWindowSeconds`), docs.

**Perubahan:** untuk file >600 s, jangan hanya 5 window dengan gap. Pilihan:
- **A:** tambah `analyzedFraction` dan window merata sampai batas CPU;
- **B:** prioritaskan head/tail + satu middle, lalu deklarasikan fraksi yang dianalisis;
- **C:** analisis adaptif berdasarkan durasi, dengan batas jumlah window yang eksplisit.

Jangan menaikkan jumlah window tanpa anggaran waktu. Untuk drop/early handover, posisi drop yang tidak dianalisis harus dilaporkan sebagai tidak tersedia, bukan ditebak.

**Tes:** file sintetis 12 menit dengan drop di segmen tengah; pastikan coverage dan `earlyHandoverUnavailableReason` benar.

### 6.3 M10 — Short-term LUFS untuk overlap

**File:** `automix_analyzer.c` (edge measurement), header/ABI, `AutomixAnalysisBridge.kt`, `models.dart`, `engine.dart` trim.

**Desain:**
- Untuk setiap edge 15 s, hitung LUFS short-term (≈3 s, atau 400 ms block dengan gating), lalu publikasikan nilai ringkasnya untuk head dan tail. Append slot baru; jangan renumber slot 0–44.
- Gunakan short-term sebagai preferensi trim bila confidence cukup; fallback ke LUFS edge 15 s, lalu RMS edge.
- Pertahankan clamp trim ±6 dB dan gate yang ada.
- Jika menambah empat slot (head/tail LUFS + confidence), ABI 45 → 49; jika hanya dua, 45 → 47. Pilih satu dan dokumentasikan.

**Tes:** sinyal 1 kHz kalibrasi, fade-out 10 s setelah chorus, track ambient; trim tidak melebihi batas dan tidak berubah untuk materi datar.

---

## 7. WS3 — Harmonik dan biaya analisis

### 7.1 M03 — Key per section/seam

**File:** `automix_analyzer.c` (`estimate_key`, `hpcp_add_frame`, edge accumulation), header/ABI, `AutomixAnalysisBridge.kt`, `models.dart`, `engine.dart`.

**Implementasi:**
1. Akumulasi chroma per 8–16 bar di 30 s pertama/terakhir (bukan seluruh window 120 s).
2. Naikkan HPCP ke 4 harmonik; tambahkan chroma bass (low-pass ~250 Hz) sebagai fitur terpisah, bukan pengganti chroma penuh.
3. Publikasikan `introKey`/`outroKey` + confidence + mode. Global key tetap sebagai fallback.
4. Merge memilih seam key hanya bila confidence melewati gate; bila tidak, gunakan key global.
5. Pitch shift satu semitone hanya boleh memakai key seam yang confident; key global yang ambigu tetap netral.

**Tes:** progresi sintetis C–Am–F–G, modulasi C→D, relative major/minor, detune ±50 sen, intro/outro sparse. Ukur exact/Camelot pada subset berlabel (P08).

### 7.2 M09 — Chord HMM dengan kualitas

**File:** `automix_analyzer.c` (`nar_automix_analyze_chords`), `engine.dart` chord merge, `models.dart`, cache.

**Implementasi:**
1. State Viterbi menjadi `(root, quality)` atau 24 state diatonis; jangan hanya 12 root.
2. Skalakan penalti transisi terhadap skala emission (target awal 0,1–0,3, bukan 0,004–0,012).
3. Tambahkan penalti nada non-chord dan fitur bass chroma bila tersedia.
4. Kualitas mengikuti state, bukan argmax greedy per segmen.
5. Confidence tetap terpisah; chord hanya memengaruhi durasi/overlap, bukan penolakan track.

**Tes:** I–vi–IV–V, C→Cm pada root sama, ii–V–I jazz, noise/percussive; chord event tetap stabil dan tidak menghasilkan lompatan kualitas palsu. Cache bump karena nilai chord berubah.

### 7.3 M06 — Profil dan optimasi biaya analisis

**Urutan wajib:**
1. Instrumentasi waktu per tahap (STFT utama, cepstrum, chord, autocorrelation) dan memori puncak. Jangan mengoptimasi sebelum ada angka.
2. Optimasi termurah: simpan HPCP per frame dari pass utama, pakai untuk chord 1–2 s; hilangkan STFT kedua.
3. Berikutnya: real-FFT packing; uji numerik dan golden.
4. Turunkan sample rate analisis hanya setelah uji akurasi chroma; perubahan ini mengubah semua fitur dan wajib cache bump.
5. Tambahkan benchmark p95 di host; target perangkat tetap P04 (<2 s/track, tanpa throttling).

Jangan mengorbankan akurasi hanya untuk benchmark sintetis. Jika corpus belum ada, simpan perubahan di belakang flag dan jangan ubah default.

---

## 8. WS4 — Tempo, downbeat, dan phrase

### 8.1 M04 — Tempo map per bar

**File:** `automix_analyzer.c` (`track_beats_dp`, `estimate_phrase_grid`, phase), header/ABI, merge.

**Langkah:**
1. Ekspos beat times dari DP (internal atau slot baru) dan bangun tempo map per 8 bar.
2. Gunakan beat times untuk phrase/downbeat; pertahankan `output[3]` sampai golden dan playback lama diperiksa.
3. Gate DP tetap: material fixed-tempo boleh memakai histogram; jangan memaksa DP pada semua track.
4. Tangani drift/ritardando dengan tes click train 120→128 BPM dan 120→90 BPM.
5. Cache bump; perbarui docs slot dan ABI test.

**Selesai bila:** fixed 120 BPM tidak bergeser, drift tidak melenceng >1 beat pada window 120 s, dan golden benchmark dijelaskan.

### 8.2 Fase 5 — Downbeat HMM/bar-level dan phrase SSM

**Prasyarat:** M04 beat times dan corpus downbeat minimal 30 track × 60 s.

**Implementasi:**
1. HMM/DP pada beat times dengan state posisi bar (2/3/4/6), emission low-band accent + timbre change.
2. Phrase SSM untuk boundary 4/8/16 bar; jangan meng-hard-code 16 beat.
3. Gate confidence dan fallback ke grid offline yang ada.
4. Jangan mengubah meter yang sudah dipublikasikan tanpa bukti dua window dan low-band corroboration.

**Metrik:** beat F1 ≥0,90 (subset 4/4), downbeat F1 ≥0,75, phrase F1 ≥0,70. Jika belum tercapai, jangan klaim selesai; simpan sebagai eksperimen.

### 8.3 M02 — Tempo arc dan biaya oktaf

**File:** `native_audio_runtime/src/automix_planner.c` (`append_variant`, `tempo_cost`, `EnergyArc`/planner input), `lib/services/automix_service/engine.dart` mirror.

**Implementasi:**
1. Bedakan varian tempo dari oktaf: `{bpm, octaveShift, isAlternate}`. Jangan memberi penalti oktaf pada alternate yang memang hasil deteksi.
2. Tambahkan biaya eksplisit untuk lompatan ½/2× (target awal 0,08–0,12), dengan pengecualian profil `openFormat` atau pasangan <100 BPM yang sah.
3. Tambahkan `TempoArc` per posisi (mis. interpolasi 118→128) dan biaya `|log2(bpm/target)|`; jangan memaksa arc pada set yang tidak punya target.
4. Mirror persis di Dart; tambah parity test dan benchmark `averageCost`.
5. Jangan mengubah bobot lain untuk “menutupi” efek tempo arc.

**Tes:** urutan 128→64→128 vs 124→126→128; pastikan lompatan oktaf dihukum, tetapi pasangan half-time yang sah tidak ditolak. Cek determinisme dan waktu planner.

### 8.4 M08b — Kalibrasi confidence

**Prasyarat:** corpus + label dari WS0/WS6.

**Implementasi:**
1. Kumpulkan skor mentah + label untuk BPM, downbeat, key, drop, vocal.
2. Kalibrasi isotonic/logistic per estimator; simpan tabel kecil di C/Dart.
3. Jangan mengganti formula default sebelum ECE <0,10 dan tidak menurunkan recall.
4. Tambahkan test kontrak bahwa semua layer memakai tabel yang sama.
5. Jika data belum cukup, tutup hanya M08a (inventaris), bukan M08b.

---

## 9. WS5 — Transisi audio dan arsitektur

### 9.1 M11 — LR4 crossover dan adaptive ducking

**File:** `native_audio_runtime/src/automix_tone_processor.c`, `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixToneManager.kt`, `CrossfadeController.kt`, `engine.dart` cue.

**Tahap 1 — LR4:**
- Ganti satu pole 150/1200 Hz dengan LR4 (dua biquad Butterworth 2nd-order per band) atau crossover LR4 yang ekuivalen.
- State filter per stream dan per kanal; tidak ada alokasi di audio thread.
- Target gain tetap atomic dan di-smooth seperti sekarang.
- Uji magnitude crossover, continuity saat reset, isolasi per stream, dan NEON/scalar parity.

**Tahap 2 — Adaptive ducking (opsional):**
- Ducking membutuhkan link antar-deck. Jangan menambah lock di audio thread.
- Pilihan aman: control-thread envelope yang mengirim target gain ke tone processor, bukan sample-accurate sidechain.
- Jika link belum tersedia, dokumentasikan sebagai deferred; jangan memalsukan ducking dengan EQ statis.

**Tes:** track vokal+instrumental, transisi 1,5–12 s, tidak ada click; `tools/automix_ffmpeg_regression.sh` tetap lulus; capture perangkat untuk artefak.

### 9.2 P09 — Post-mix true-peak: spike dan keputusan

**Kondisi saat ini:** limiter per-deck causal (4× Lagrange, ceiling 0,95), tanpa lookahead; dua deck disum sebagai AudioTrack terpisah oleh AudioFlinger. Tidak ada jaminan true peak gabungan.

**Spike wajib sebelum coding:**
1. Render dua deck correlated (sine, kick, clipped master) dan ukur intersample peak gabungan. Target: tidak ada overshoot >0,3 dB; jika ada, kuantifikasi.
2. Evaluasi opsi dengan Media3 1.11.1 via Context7:
   - shared software mix bus sebelum AudioSink;
   - dua decoder tap ke satu AudioProcessor chain;
   - batasan audio offload/bit-perfect.
3. Tulis keputusan: implementasi shared bus, atau terima risiko dengan dokumentasi eksplisit.
4. Jangan mengaktifkan native fade atau mengklaim true-peak aman tanpa capture.

**Jika implementasi disetujui:** PR terpisah, desain dua stream → satu bus → limiter oversampled → output. Perubahan ini berisiko pada offload, latency, dan bit-perfect; butuh approval tersendiri.

### 9.3 M14 — Jangan campur dengan pekerjaan P09

- Keputusan M14 (hapus jalur dormant) tidak menunggu P09 dan dikerjakan di WS1.
- Jika shared bus P09 disetujui, itu jalur baru yang terpisah. Jangan mengaktifkan kembali native per-deck fade sebagai pengganti limiter post-mix.
- Tetap pertahankan pemisahan “per-deck envelope” vs “post-mix limiter” di dokumentasi dan kode.

---

## 10. WS6 — Matriks validasi P01–P10

| ID | Metode | Kriteria lulus | Environment |
|---|---|---|---|
| P01 | Corpus 120 track, bandingkan BPM dengan aubio/madmom + cek manual | ≤10% track error >2%; 0 error oktaf pada 4/4 | Host + corpus |
| P02 | Render 20 transisi fitur seam lama vs edge, A/B buta | Preferensi ≥65%; tidak ada trim salah >3 dB | ffmpeg/JVM + pendengar |
| P03 | Library 500–2.000 track; ukur ukuran cache, waktu plan, frame drop | Plan <100 ms; tidak ada frame >32 ms; cache wajar | Perangkat/emulator |
| P04 | `simpleperf`/`atrace` 5 track 10 menit | p95 <2 s/track; tidak throttle pada sweep 40 track | Mi 9T |
| P05 | Capture PCM dua deck saat fade, dengan/tanpa live tracker | Median offset <20 ms; tidak ada artefak baru | Perangkat + capture |
| P06 | A/B phase lock on/off pada 30 pasangan | Offset akhir <1/8 beat; MOS tidak turun | Perangkat + pendengar |
| P07 | Log timestamp reorder per sesi | ≤2 reorder/10 menit setelah 3 track pertama | Perangkat |
| P08 | 30 track label key/chord | Key exact ≥80%; Camelot ≤1 ≥90% | Corpus |
| P09 | Render dua deck correlated; ukur intersample peak | Tidak ada overshoot >0,3 dB | ffmpeg/offline |
| P10 | Plan diff 50 library, sebelum/sesudah polish | 0 pengulangan artis jarak ≤2 saat `avoidArtistRepeat` | Fixture/planner |

**Aturan pelaporan:** bedakan “lulus”, “gagal”, “tidak dijalankan”, dan “tidak dapat dijalankan di environment”. Jangan mengubah status menjadi tertutup hanya karena kode sudah ada.

### Verifikasi yang masih terutang saat blueprint dibuat

- Tes Kotlin/Gradle belum berhasil dijalankan karena disk penuh; jangan mengulang klaim lulus tanpa eksekusi.
- `tools/automix_ffmpeg_regression.sh` belum dijalankan.
- Capture PCM perangkat, listening test, dan profiling Mi 9T belum ada.
- APK tidak boleh dibangun di environment ini.

---

## 11. Definition of Done per temuan

Sebuah temuan boleh ditandai **selesai** hanya jika semua berlaku:

1. Kode perubahan ada dan sesuai kontrak layer (Dart/Kotlin/C/FFI).
2. Tes baru menguji perilaku yang berubah, bukan hanya compile.
3. Perintah verifikasi di §1 dijalankan; hasilnya dicatat.
4. Tidak ada regresi golden yang tidak dijelaskan.
5. ABI/cache schema diperbarui di semua layer jika relevan.
6. `docs/automix-production-wiring.md` akurat; tidak ada klaim fitur yang belum aktif.
7. `pubspec.yaml` + changelog diperbarui untuk perubahan perilaku.
8. Memory AutoMix dan index `MEMORY.md` diperbarui.
9. Untuk P01–P10: data/metrik tersedia, bukan hanya opini.
10. Tidak ada APK build, tidak ada commit/push tanpa permintaan.

Status yang diperbolehkan:

- **Open:** belum ada implementasi.
- **Implemented, unvalidated:** kode/tes ada, data lapangan belum.
- **Validated:** metrik lulus pada environment yang disebut.
- **Accepted risk:** keputusan sadar, didokumentasikan, bukan “fixed”.

---

## 12. Template prompt handoff untuk agent berikutnya

```text
Kerjakan [ID temuan / workstream] AutoMix pada repo ini.

Baca dulu:
- AGENTS.md
- docs/superpowers/plans/2026-10-31-automix-open-findings-blueprint.md
- docs/automix-production-wiring.md
- .agents/memory/automix-fase3-6-v23.md

Batasan:
- Jangan ulangi implementasi dasar di §2.1; kerjakan residual yang relevan di §2.2.
- Jangan build APK.
- Jangan commit/push tanpa instruksi.
- Perubahan perilaku wajib bump versi + changelog + docs + memory.
- Perubahan ABI/cache wajib mengikuti checklist §1.
- Jalankan verifikasi yang relevan dan laporkan yang tidak bisa dijalankan.

Target:
[precise deliverable]

Definition of done:
[acceptance criteria dari workstream]

Laporkan:
- file yang diubah;
- tes/perintah yang dijalankan dan hasilnya;
- risiko/regresi yang belum tertutup;
- status: Open / Implemented, unvalidated / Validated.
```

---

## 13. Ringkasan satu halaman

- **Jangan ulang implementasi dasar:** H02/H03/H04/H05/M01/M07/M10/M11/M12/M13/M15/M16/M18 sudah punya mekanisme di kode. Residual H05/M10/M11 tetap ada di §2.2.
- **Mulai dari:** M17 + baseline, lalu L01/L02/L04/L05, lalu M14, M05, L06/M10.
- **Pekerjaan besar:** M03/M09 (harmonik), M04 + downbeat/SSM (tempo/phrase), M02 (planner), M11 (LR4), P09 (shared bus).
- **Tidak bisa diklaim tanpa data:** P01–P10, terutama BPM nyata, key/chord, live phase alignment, dan post-mix true peak.
- **Prinsip:** satu PR kecil, satu kontrak, satu alasan; golden hanya berubah dengan penjelasan; kejujuran status lebih penting daripada menutup semua baris.
