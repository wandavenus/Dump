# AutoMix Fase 3–6 + Open Findings (v1.5.67, cache schema v24)

Riwayat Fase 3–6 berikut berasal dari `d27de4c` (v1.5.66, cache v23). Update open
findings per 1 November 2026 di bagian akhir mencatat pekerjaan 1.5.67 yang belum
di-commit. Lanjutan dari `automix-fase2-contract-v22.md`.

## Fase 3 — drop/early handover

- Analyzer menyimpan hingga **tiga kandidat drop per window**, dedupe jarak onset 1,5 s.
  ABI analyzer naik **41 → 45**; slot 41/42 dan 43/44 adalah offset/confidence kandidat
  kedua dan ketiga. Header, FFI, map Kotlin, dan parser Dart harus tetap sinkron.
- `automixMergeSegments` mengubah kandidat ke waktu absolut file dan memilih **drop paling
  awal yang confident** di envelope **8.000–150.000 ms**. Gate 90 s yang lama dihapus dari
  engine, service, dan `Media3PlaybackService`.
- Early handover boleh phrase-snap sampai **satu frasa penuh (`metre × 4` beat)** lewat
  `phraseAlignedStartMs(..., maxShiftBeats)`; fallback near-EOF tetap 4 beat.
- Alasan early handover tidak tersedia diekspos sebagai
  `earlyHandoverUnavailableReason` dan dicatat verbose sekali per perubahan.
- Tes: `test_analyzer_multiple_drop_candidates`, parser tiga kandidat, merge earliest,
  gate Kotlin, dan phrase snap Kotlin (tes Kotlin belum dijalankan di sandbox).

## Fase 4 — cache dan perencanaan

- Cache pindah dari SharedPreferences ke **satu file per lagu**:
  `${appSupport}/automix_cache/automix_<id>.json`. Tulis atomic (temp + rename), decode
  `jsonDecode` di `Isolate.run`. Metadata MediaStore tidak disimpan di cache.
- Migrasi sekali dari key legacy `automix_<id>`, lalu `prefs.remove`. Prune sekali per
  service menghapus `*.tmp` dan ID yang sudah tidak ada di MediaStore.
- Perencanaan hanya prefix **20 lagu**, minimal **4 decoded**. Reorder hanya diterapkan
  bila biaya membaik **≥5%** atau tiga posisi teratas berubah (`scoreOrder` hysteresis).
- Cache schema **v22 → v23**. Fixture dan test memakai `version: 23`.

## Fase 5 — beat/downbeat/phrase (parsial)

- Ditambahkan `track_beats_dp`: DP gaya Ellis, kandidat periode ±35%, penalti log-ratio,
  gate confidence. `estimate_phrase_grid` menerima `beat_indices` dan memakai timestamp
  beat aktual untuk bar/frasa.
- **Gate penting:** DP hanya dipakai bila `output[23] (tempo stability) < 0.85`. Material
  fixed-tempo tetap memakai histogram phase lama. Tanpa gate ini, downbeat click 120 BPM
  bergeser ~58 ms dan golden gagal; penyebabnya perbedaan pusat frame vs timestamp onset.
- `output[3] (phase)` sengaja tidak diubah agar playback/tes lama tidak regresi.
- BPM gabungan antar-window sekarang **weighted median**, bukan rata-rata. Bila agreement
  < 70%, confidence dipotong setengah agar planner memperlakukan tempo sebagai netral
  (kasus 120/120/90 tidak lagi menjadi 110).
- Belum dikerjakan: key per section dan chord-quality HMM; butuh corpus berlabel.

## Fase 6 — planner/transisi (parsial)

- Beam search **width 8, depth 2** di C (`NAR_PLAN_BEAM_WIDTH/DEPTH`) dan mirror Dart.
  Cost dua langkah: `cost1 + 0.35·min(cost2 + 0.35·cost3)`.
- Polish swap/insert/reverse dan cooldown artis tetap; budget tidak berubah di fase ini.
- Belum dikerjakan: tempo arc per posisi, crossover LR4, short-term loudness tambahan,
  dan post-mix limiter. Limiter pasca-mix tidak mungkin tanpa perubahan arsitektur dua
  AudioTrack; jangan klaim sudah ada.

## Verifikasi yang benar-benar dijalankan

- `native_audio_runtime` C suite: lulus (warning lama `nanosleep`).
- `cd native_audio_runtime && dart test -j 1`: **65 lulus**.
- `flutter test test/services/automix_service`: **149 lulus**.
- `dart analyze lib test`: bersih.
- `dart run tools/automix_bench.dart --check`: **12 kasus lulus, golden tidak berubah**;
  8/8 BPM ≤2%, 8/8 metre, 10/10 key, rata-rata ~99 ms.
- Belum dijalankan: Kotlin/Gradle (percobaan `:app:testDebugUnitTest --tests ...AutomixTransitionPolicyTest`
  gagal saat wrapper mengunduh Gradle: `No space left on device`, root hanya ~36 KB),
  `tools/automix_ffmpeg_regression.sh`, capture perangkat, APK (dilarang di environment ini).

## Blueprint sisa temuan

Rencana eksekusi lengkap untuk semua temuan yang masih terbuka ada di
`docs/superpowers/plans/2026-10-31-automix-open-findings-blueprint.md`. Isinya memetakan
workstream, urutan PR, file, ABI/cache checklist, tes, kriteria lulus P01–P10, dan aturan
status (Open / Implemented, unvalidated / Validated). Gunakan dokumen itu sebagai titik
mulai; jangan mengulang implementasi dasar yang sudah ada, dan kerjakan residual parsial
sesuai matriksnya.

## Open findings update (v1.5.67, 2026-11-01)

- **L01:** `automix_analyzer.c` memakai ulang empat estimasi tempo kuartal. Golden 45-slot
  identik untuk sinyal stabil dan drift; benchmark 12/12 dan suite Dart native 65/65
  lulus menurut laporan Agent 2. Status: Implemented, unvalidated.
- **M05:** downsampler Android memakai Butterworth orde 4 pada 0,40× output rate, anti-phase
  fallback dengan smoothing 20 ms dan hysteresis; schema cache dinaikkan dari v23 ke v24
  agar analisis lama diulang. Tes Kotlin 8/8 dan host-JVM/JNI 3/3 fixture stereo lulus;
  belum ada capture di Xiaomi Mi 9T. Status: Implemented, unvalidated.
- **L06:** bridge membatasi analisis hingga 5 window × 120 detik yang disebar ke seluruh
  file, menghitung `analyzedFraction` sebagai union interval, dan tidak menebak drop cue di
  luar coverage. Tes Kotlin fokus 3/3 lulus menurut Agent 3; regresi planner Dart untuk
  720 detik, `analyzedFraction` 0,82, dan no-confident-drop lulus sebagai bagian suite
  AutoMix 154/154. Belum ada full 12-minute MediaCodec/JNI decode.
  Status: Implemented, unvalidated.
- **L02:** ring-buffer ages di luar `history_count` kini netral; compound fixture memberi
  empat bar 2-beat pada window 6 detik agar meter 2 dapat diukur dari history aktif. Full
  host C suite dan native Dart 65/65 lulus; ASan/UBSan tidak dapat ditautkan karena Clang
  runtime tidak tersedia. Belum ada validasi Xiaomi/device. Status: Implemented, unvalidated.
- **L05:** fallback `−18 − gainDb` kini dibatasi ke −60…−6 LUFS, sehingga ambient sangat pelan
  tidak lagi terangkat ke floor −24 LUFS. Suite AutoMix Flutter terbaru 154/154 dan analyze bersih
  menurut laporan Agent 4. Status: Implemented, unvalidated.
- **M11:** native tone processor memakai crossover LR4 tiga-pita pada 150 Hz dan 1,2 kHz,
  state terpisah per stream/kanal, serta jalur stereo NEON ARM64. Suite C, Dart native,
  QEMU NEON/scalar parity, compile NDK ARM64, NEON differential, dan regresi FFmpeg lulus
  menurut laporan Agent 5; suite Gradle tetap memiliki satu assertion baseline gagal
  (`AutomixTransitionPolicyTest.kt:212`). Capture Mi 9T tidak dijalankan (`adb` tidak ada).
  Adaptive ducking ditunda; P05 dan validasi perangkat masih terbuka.
- **M17:** suite test native dijalankan serial melalui `native_audio_runtime/dart_test.yaml`
  (`concurrency: 1`); default `dart test` lulus 10/10 run pada checkout bersih `11e4298`
  (65 tes per run). Race lama tidak tereproduksi sebelum perubahan pada sampel lokal.
- **P10:** tervalidasi pada fixture planner 50 lagu/10 artis: urutan berubah, semua lagu
  muncul tepat sekali, tidak ada artis berulang dalam dua posisi berikutnya, dan output
  native sama dengan referensi Dart. Test khusus lulus dan suite AutoMix 154/154. Cakupan
  status hanya fixture ini, bukan library nyata; P01–P09 tetap menunggu data/perangkat.
- Detail baseline, termasuk assertion Kotlin yang gagal pada checkout awal serta status
  regresi FFmpeg, tercatat di `docs/automix-validation-baseline.md`. P01–P09 belum ditutup;
  synthetic golden bukan bukti akurasi musik nyata. M11 LR4 dan P09 tetap temuan terpisah.

## Jebakan

- Jangan menaikkan `output[3]` ke phase DP tanpa memperbarui golden dan memeriksa
  pergeseran timestamp frame.
- Jangan memakai DP phrase untuk semua track; gate stability adalah bagian dari kontrak
  agar fixed-tempo tidak regresi.
- File cache harus atomic; jangan menulis JSON langsung ke path final.
- ABI 45 harus diperbarui di empat tempat: C header/analyzer, JNI, FFI Dart, dan map Kotlin.


## M17 — determinisme suite native (2026-11-01)

- `native_audio_runtime/dart_test.yaml` menetapkan `concurrency: 1`, karena test suite berbagi state C global (`g_states`, `g_tracker`, `g_published`). Perintah default `dart test` di `AGENTS.md` otomatis serial tanpa flag tambahan.
- Checkout bersih `11e4298`: setelah konfigurasi, `dart test` default lulus 10/10 pengulangan (65 tes tiap run); `dart test -j 1` juga lulus 65. Sebelum konfigurasi, 10/10 run default pada environment ini juga lulus, jadi race historis tidak tereproduksi pada sampel tersebut.
- Baseline benchmark sintetis: `dart run tools/automix_bench.dart --check` lulus 12/12; C suite lulus dengan `-D_POSIX_C_SOURCE=200809L`; `TMPDIR=/dev/shm flutter test test/services/automix_service` lulus 149; `dart analyze lib test` bersih.
- Tes Kotlin fokus menghasilkan 22 tes, 1 assertion gagal (`early handover phrase snap can reach a full four-bar boundary`, `AutomixTransitionPolicyTest.kt:212`). Regresi FFmpeg terhenti di compile Gradle karena delapan class plugin tidak ada di classpath `GeneratedPluginRegistrant`; rincian dan status P01–P10 ada di `docs/automix-validation-baseline.md`.
- Manifest benchmark yang tersedia memuat 12 sinyal sintetis saja; belum ada korpus audio berlabel atau validasi perangkat/listener. Tidak membangun APK.


## Corpus AutoMix — provenance dan cakupan label (2026-11-01)

- Corpus 120 sampel sudah dikumpulkan di `/workspace/automix-corpora` di luar repo: 35 Candombe, 20 AAM Tiny sintetis, 35 FSLD loops metadata-only, 30 GuitarSet clips. Meki melaporkan semua SHA-256 cocok; audit lokal menemukan 120 entry, semua file ada, total 2,008,569,696 byte (~1.87 GiB).
- Candombe inventory tim: 19.167 beat dan 4.818 downbeat pada materi 4/4; record Zenodo resmi menyebut 35 performa, stereo FLAC 44.1 kHz/16-bit, lebih dari 4.700 downbeat, lisensi CC BY 4.0.
- 20 AAM Tiny mix berisi 5.776 beat, 1.444 downbeat, chord per beat. FSLD (~87 MB) punya metadata BPM/key/mode/4-4 konsensus tanpa beat event. GuitarSet klip terpilih berasal dari mono-mic, dengan beat/downbeat click-track. Hanya Candombe dihitung sebagai anotasi ahli independen untuk event-level F1.
- Smoke 10-case AAM Tiny: seluruh event beat/downbeat cocok dengan label ARFF asli. BPM raw ±2% 5/10, octave-folded 9/10; empat raw octave choices punya alternate dekat, satu miss `0620` tetap (~33.35%) dan sumbernya berubah tempo 123/164. Key 2/10 tidak mewakili sequence accuracy karena semua klip punya beberapa key segment. Metre 3 detections + 7 `null` abstentions. Downbeat phase references hanya 2: `0192` error 1,283 ms, `1014` 29 ms. Jangan ubah label; ini diagnostic, bukan full-corpus P01.
- Untuk event-level beat/downbeat F1, Candombe adalah satu-satunya subset saat ini yang dihitung sebagai anotasi ahli independen. AAM label sintetis; GuitarSet hanya supplement gitar (360 klip ~30 s, CC BY 4.0) dengan beat/downbeat dari click track dan chord performed diinferensikan. Ada dua timing annotations dan satu MIDI duplicate yang diketahui.
- Setiap sampel perlu provenance/DOI, lisensi/atribusi, cakupan dan metode label; audio tidak masuk repo tanpa peninjauan hak redistribusi. Harness bench sekarang belum mengevaluasi F1 dari deret event beat/downbeat, jadi laporkan coverage terpisah.
