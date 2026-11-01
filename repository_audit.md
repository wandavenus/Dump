# Repository Audit & Code Modernization — Dump

**Status: PR #292 sudah squash-merge; pengembalian UI selektif diajukan terpisah untuk ditinjau dan belum di-merge.**

- Tanggal: 1 November 2026
- Branch: `audit/dump-modernization`
- Pull request: [#292](https://github.com/wandavenus/Dump/pull/292), sudah squash-merge
- Baseline branch: `main` / `origin/main` pada `5eb3f82`
- Gate kandidat akhir PR #292 mencakup perbaikan sampai `9161a93` dan integrasi versi/changelog, workflow, localization, UI, memory, serta tes Delete. Branch tindak lanjut ini memulihkan hanya perilaku/tata letak UI yang diminta, beserta tes, string, dan catatan khusus UI; perubahan teknis non-UI tetap dipertahankan.

## Ringkasan saat ini

Temuan yang sudah dapat dipastikan: **8 perbaikan non-UI tetap berlaku** pada CI/release, Gradle, decoder, audio, dan planner; **5 risiko** belum selesai atau menunggu validasi yang lebih mewakili perangkat, termasuk tindak lanjut UX-01 yang dikembalikan pada branch ini. Dari 13 temuan yang dicatat: kategori CI/CD 3, Gradle 1, Android/audio/decoder 3, AutoMix 2, performa 1, UI/UX 2, dan dependency 1; prioritasnya **1 tinggi, 8 sedang, 4 rendah**. Tidak ada migrasi API deprecated Kotlin/Flutter yang dilaporkan sebagai wajib pada scope yang sudah ditinjau. Satu sumber warning yang dibersihkan ialah assignment DSL Gradle lama dan notasi dependency project; warning AGP/Flutter/plugin pihak ketiga yang tersisa tidak disembunyikan atau dipaksa bersih.

Gate integrasi terakhir pada kandidat working tree terbaru lulus:

| Pemeriksaan | Hasil |
|---|---|
| `flutter analyze` | Lulus, tanpa isu |
| Flutter tests | 338 lulus setelah 4 tes khusus UI dari PR #292 dilepas bersama perubahan yang dibatalkan |
| Kotlin unit tests | 468 lulus; 0 gagal, 0 error, 0 skip (`--rerun-tasks`) |
| Gradle `assembleDebug` | `BUILD SUCCESSFUL`; JNI FFmpeg `UP-TO-DATE` |
| Debug APK / packaging | Lulus; `libffmpegJNI.so` arm64-v8a dan tiga notice lisensi terkemas |
| Dart native / benchmark / C | 65/65 lulus; golden AutoMix 12/12; native C regression lulus |
| FFmpeg offline regression | Lulus; current max-step 0.023081, gamma/trims 0.018705 (batas 0.05); kedua legacy fault model terdeteksi |
| GitHub Actions static lint | `actionlint` lulus untuk seluruh workflow |
| Shell scripts / whitespace | `bash -n` dan `git diff --check` lulus |

Gate dijalankan dengan Flutter 3.47.9 dan lockfile hash `c10a4626cd3615522973efc4c8e4011e2a9e20e8a2e1da1132ef18ae7b5f3782`. Kotlin suite dijalankan ulang tanpa cache pada tree kerja dengan Android SDK/NDK diarahkan; snapshot terisolasi terbaru juga mengulang seluruh gate setelah changelog diperbarui. Pada branch tindak lanjut, `flutter analyze --no-pub` lulus dan Flutter tests lulus 338/338 setelah penghapusan tes khusus UI yang terkait. Build warnings Gradle/AGP dan plugin Flutter yang masih ada tidak ditekan; detail migration yang belum selesai dicatat di bagian risiko.

## Temuan dan tindakan

| ID | Prioritas / keyakinan | Temuan dan akar sebab | Dampak | Tindakan / status |
|---|---|---|---|---|
| CI-01 | Tinggi / tinggi | Condition perubahan Dart terbalik membuat Flutter tests dan integrasi Android terlewati pada PR yang justru mengubah Dart. | Perubahan Flutter bisa lolos tanpa tes lintas batas Dart/Android. | Guard ditiadakan; semua PR ke `main` dan dispatch menjalankan test/build serta pemeriksaan paket JNI/lisensi. Lulus `actionlint` dan gate akhir. |
| CI-02 | Sedang / tinggi | Sejumlah GitHub Actions masih memakai major yang menjalankan Node 20, yang telah memasuki masa penghentian pada runner GitHub. | Workflow dapat gagal saat runtime lama dilepas dan membawa dependency action usang. | Major action diperbarui ke rilis Node 24 yang sesuai; pin Flutter dibuat satu sumber di `pubspec.yaml` (3.47.9). |
| CI-03 | Sedang / tinggi | Izin token workflow terlalu luas untuk tahap yang hanya membangun/menganalisis; output commit multiline dan JSON dispatch berisiko rusak oleh nilai ref yang tidak di-escape. | Memperbesar dampak kompromi action dan berpotensi membuat output/payload salah format. | CodeQL dibatasi ke `contents:read` + `security-events:write`; izin Pages hanya di job deploy; APK build memakai `contents:read`, draft release terpisah memakai `contents:write`; JSON dibuat dengan `jq --arg`, delimiter output commit acak. |
| GR-01 | Rendah / tinggi | Gradle memakai assignment DSL lama dan notasi dependency project yang menghasilkan warning. | Noise warning menutupi masalah baru dan menyulitkan pemeliharaan konfigurasi. | DSL dan notasi dependency diperbarui; `./gradlew help --warning-mode all --console=plain` lulus. Warning AGP/Flutter/plugin pihak ketiga dicatat sebagai eksternal dan tidak disamarkan. |
| AUD-01 | Sedang / tinggi | Durasi crossfade `NaN`, tak hingga, negatif, atau finite ekstrem dapat menghasilkan jadwal transisi yang tidak masuk akal; nilai ekstrem dapat jenuh ke `Long.MAX_VALUE`. | Fade bisa dimulai terlalu dini atau durasi tidak mewakili pilihan pengguna. | Input invalid dinonaktifkan dan durasi dibatasi ke maksimum produk 12 detik di MethodChannel serta controller; tes terarah Kotlin 50/50 lulus. |
| AUD-02 | Sedang / tinggi | Jalur exception pada decode bisa melewati pembersihan `MediaExtractor` jika release tidak dijaga di setiap cabang. | Resource native dapat tertahan saat metadata, callback, atau pemilihan track gagal. | `try/finally` mencakup seluruh jalur lifecycle extractor; tes fokus 21/21 di empat suite PCM/AutoMix lulus, lalu Kotlin full suite 468/468 tanpa cache setelah perubahan final. Commit lokal `86cdeda`; full gate kandidat terbaru lulus. |
| AM-01 | Sedang / tinggi | Local polish swap/insert/reverse menghitung ulang skor terlalu pendek, padahal penalti cooldown artis bergantung pada empat slot sebelumnya. | Perbaikan urutan yang lebih baik dapat terlewat; direproduksi pada fixture deterministik di Dart dan C. | Evaluasi di Dart dan C diperluas ke horizon cooldown empat slot; tes regresi/parity lulus. Suite AutoMix 156/156 setelah tambahan coverage. |
| AM-02 | Sedang / tinggi | Planner menjumlahkan durasi segmen analisis mentah, walau interval dapat overlap dengan ring-tail capture. | `analyzedFraction` dapat terlalu tinggi dan memengaruhi keputusan coverage. | Coverage dihitung sebagai union interval; fixture overlap menghasilkan 565/700, bukan 600/700. Tes regresi lulus. |
| UX-01 | Rendah / tinggi | Beberapa kontrol tidak mencapai target sentuh 48 dp atau kekurangan label aksesibel; penghapusan lagu, menu layar pendek, inset portrait, dan setelan pengurangan animasi belum ditangani konsisten. | Sulit dipakai dengan pembaca layar, kontrol kecil, atau perangkat berlayar pendek; animasi dapat mengganggu pengguna sensitif gerakan. | Perubahan UI terkait pada PR #292 dibatalkan atas permintaan pengguna; perilaku/tata letak sebelum PR dipulihkan. Isu ini kembali menjadi tindak lanjut yang menunggu keputusan baru; tes UI spesifik dilepas bersama implementasinya. |

## Dependency health

`flutter pub outdated --show-all` menunjukkan **21 dependency terkunci** memiliki versi baru dalam batas constraint saat ini, sementara **3 constraint** tidak dapat mencapai versi terbaru yang tersedia. Lockfile kemudian diperbarui dalam batas constraint yang sudah ada (`flutter pub upgrade`), tanpa mengubah constraint major di `pubspec.yaml`; 22 paket berpindah/ditambahkan.

Dua direct dependency yang ditahan sengaja: `permission_handler` 13 memerlukan Android `compileSdk 37`, sedangkan aplikasi saat ini memakai `compileSdk 36`; `cupertino_icons` 2 memindahkan implementasi ke `cupertino_ui`, sehingga migrasi visual perlu diperiksa terpisah. Tidak ada alasan untuk mengambil perubahan mayor ini tanpa build/kompatibilitas dan pemeriksaan UI khusus. Paket `material_color_utilities` dan `test_api` juga ditahan oleh constraint SDK Flutter saat ini.

Pencocokan OSV baca-saja terhadap **94 paket hosted** di lockfile tidak menemukan advisory yang cocok dengan versi terkunci; ini bukan jaminan universal bebas CVE. Ada advisory upstream terkait `permission_handler_android` 14.1.0 yang disebut diperbaiki di 14.1.1, sementara lockfile memakai 13.0.1; tidak disimpulkan bahwa versi lebih lama otomatis aman atau terdampak tanpa rentang advisory yang cocok. Major action yang terverifikasi dan kompatibel dengan Node 24 sudah diperbarui. Pin action pihak ketiga ke full commit SHA masih merupakan hardening opsional yang perlu diputuskan bersama kebijakan auto-update/Dependabot.

## Risiko dan pekerjaan tersisa

| ID | Prioritas / keyakinan | Risiko / bukti saat ini | Langkah berikutnya |
|---|---|---|---|
| MEDIA-01 | Sedang / sedang | `PcmDecoder` mengambil sample rate/channel dari format extractor, membaca output sebagai `ShortBuffer`, dan mengabaikan `INFO_OUTPUT_FORMAT_CHANGED`. Dokumentasi Android menyatakan output berikutnya mengikuti format baru; belum ada reproduksi di codec target. | Tambah fake-codec/mapper regression untuk output format awal dan perubahan format, sample rate/channel serta PCM encoding; validasi pada perangkat/codec representatif. Jangan campur frame dengan format berbeda. |
| PERF-01 | Sedang / sedang | Batas lima window × 120 detik membatasi sampel yang disimpan/dianalisis, bukan lamanya `PcmDecoder.decode()`, yang tetap berjalan sampai EOS demi ring-tail. Trek 60 menit masih dapat membutuhkan decode 60 menit. | Benchmark penggunaan CPU/waktu dan memori pada perangkat kelas menengah serta file panjang sebelum mengubah strategi sampling. |
| UX-02 | Rendah / sedang | Jembot melaporkan kategori Search yang tidak beraksi, konten/judul Radio, affordance Browse, dan profil shader sebagai tindak lanjut; belum diputuskan sebagai defect atau diuji. | Triage perilaku yang diharapkan dan profil visual di perangkat sebelum mengubah UI. |
| DEP-01 | Rendah / tinggi | Action references masih berupa major tags, bukan full commit SHA. Tag resmi memudahkan update tetapi tidak memberikan immutability SHA. | Pertimbangkan pin SHA bersama Dependabot atau workflow dependency lockfile agar update tetap terpelihara. |

## Perubahan dan file

Cakupan PR #292 mencakup `.github/workflows/`, `pubspec.yaml`/`pubspec.lock`, Gradle Android, Kotlin `PcmDecoder`, planner AutoMix Dart/C, changelog, localization, widget/UI, tes regresi aksesibilitas, memory docs, serta laporan ini. Branch tindak lanjut mengembalikan hanya widget UI terkait dan menghapus string localization, tes, serta catatan yang khusus untuk perubahan tersebut; folder skill tak terlacak dan semua perubahan non-UI tetap dikecualikan dari revert.

Performa runtime dan penggunaan memori belum diukur pada perangkat. Perbaikan planner menutup kesalahan cakupan skor yang direproduksi; hasil itu tidak membuktikan peningkatan urutan untuk katalog musik umum. Pengembalian UI ini belum melewati inspeksi visual perangkat.

## Status PR dan langkah final

PR #292 menargetkan `main` dan sudah squash-merge. Perbaikan terpisah berada pada commit `a00dfcd`, `72fe153`, `5c57104`, `86cdeda`, dan `9161a93`, bersama perubahan CI/release, dependency lock, UI/accessibility, regression test, dan dokumentasi audit. PR tindak lanjut dari `revert/pr-292-ui` hanya memulihkan UI yang disebutkan; tinjau hasil CI sebelum keputusan merge dan jangan merge tanpa izin terpisah. Risiko MEDIA-01, PERF-01, UX-01, UX-02, dan DEP-01 tetap terbuka/deferred seperti dijelaskan di atas.

## Referensi resmi yang dipakai

- [GitHub Actions Node 20 deprecation](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/), [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions), dan [CodeQL action permissions](https://github.com/github/codeql-action#usage).
- [Gradle setup action v6](https://github.com/gradle/actions/blob/v6/setup-gradle/README.md) dan [Flutter 3.47.9 release](https://github.com/flutter/flutter/releases/tag/3.47.9).
- [Dart `pub upgrade`](https://dart.dev/tools/pub/cmd/pub-upgrade), [permission_handler changelog](https://pub.dev/packages/permission_handler/changelog), dan [cupertino_icons changelog](https://pub.dev/packages/cupertino_icons/changelog).
- [OSV database](https://osv.dev/) dan [Dart pub security advisories](https://dart.dev/tools/pub/security-advisories).
- [Android `MediaCodec` API](https://developer.android.com/reference/android/media/MediaCodec) dan [Android `MediaFormat` API](https://developer.android.com/reference/android/media/MediaFormat).
