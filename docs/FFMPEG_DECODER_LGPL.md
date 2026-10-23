# Decoder FFmpeg LGPL (Phase 9)

Dokumen ini menggantikan rencana lama `docs/PHASE_9_FFMPEG_DECODER_INTEGRATION.md`
(file tersebut tidak pernah dibuat) dan mencatat perubahan dari **AAR prebuilt
Jellyfin (GPL-3.0)** ke **AAR yang dibangun sendiri dengan FFmpeg LGPL**.

## Kenapa diganti

`android/app/build.gradle` sebelumnya memakai
`org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1`. POM artefak itu menyatakan
lisensi **GPL-3.0**, sementara `LICENSE` repo ini "All Rights Reserved" dan
`.github/workflows/android.yml` mengunggah APK ke GitHub Release. Itu konflik
lisensi pada karya gabungan (temuan **C1** di `AUDIT_REPORT_2026-10-23.md`).

Konfigurasi FFmpeg di dalam artefak Jellyfin sebenarnya tidak memakai
`--enable-gpl`, tetapi metadata lisensi artefak tetap mengikat secara hukum, dan
kita tidak bisa mengandalkan klaim pihak ketiga untuk kepatuhan. Karena itu
decoder kini dibangun dari sumber di repo ini.

Keuntungan lain:

- Wrapper dibangun dari **androidx/media 1.11.1**, sama dengan `media3_version`
  aplikasi — menghilangkan version skew 1.9.0 vs 1.11.1 (**M6**).
- FFmpeg dikonfigurasi `--disable-everything` + decoder eksplisit, jadi kode
  yang tidak dipakai (termasuk MagicYUV yang terkena CVE-2026-8461) tidak ikut
  ke dalam `.so` (**M8**).
- Tidak ada lagi dependensi decoder pihak ketiga di `build.gradle`.

## Artefak

| Artefak | Lokasi | Isi |
|---|---|---|
| AAR decoder | `android/decoder-ffmpeg/libs/media3-decoder-ffmpeg-release.aar` | kelas wrapper `androidx.media3.decoder.ffmpeg` (Apache-2.0) + `libffmpegJNI.so` |
| Modul Gradle | `android/decoder-ffmpeg/build.gradle` | mengekspos AAR sebagai `project(':decoder-ffmpeg')` |
| Skrip build | `android/build-ffmpeg-jni.sh` | membangun FFmpeg + wrapper, menghasilkan AAR dan bundle kepatuhan |
| Bundle kepatuhan | `build/ffmpeg-decoder-lgpl/` (gitignored) | sumber FFmpeg, sumber wrapper, `COPYING.LGPLv2.1`, `LICENSE.Apache-2.0`, `BUILD_INFO.txt` |

AAR **di-commit** supaya build rilis tidak membutuhkan NDK. Ukurannya hanya
beberapa MB dan ABI lain dibuang oleh `abiFilters "arm64-v8a"`.

## Format yang didukung

Hanya format yang tidak punya decoder MediaCodec layak di perangkat target
(ALAC/DTS/TrueHD/Vorbis/Opus). Decoder yang diaktifkan:

```
alac dca mlp truehd vorbis opus
```

Semuanya tersedia di FFmpeg tanpa komponen GPL. FLAC/AAC/MP3 sengaja **tidak**
diaktifkan: `EXTENSION_RENDERER_MODE_PREFER` membuat FFmpeg didahulukan untuk
format apa pun yang didukungnya, sehingga mengaktifkan FLAC akan memindahkan
pemutaran FLAC dari decoder platform ke software FFmpeg tanpa manfaat.

APE/WavPack/TAK/Monkey's Audio tetap di luar scope: Media3 tidak punya
`Extractor` untuk container tersebut, jadi itu pekerjaan terpisah.

## Cara build

Prasyarat: Android NDK r26+ (repo memakai 28.2.13676358), Android SDK dengan
CMake 3.21+, JDK 17+ (JDK 21), `git`, `make`, `tar`. Linux/macOS.

```bash
export ANDROID_NDK_HOME=/path/to/android-sdk/ndk/28.2.13676358
bash android/build-ffmpeg-jni.sh
```

Atau langsung: `bash android/build-ffmpeg-jni.sh /path/to/ndk`.

Override lewat env var:

| Variabel | Default | Catatan |
|---|---|---|
| `MEDIA3_TAG` | `1.11.1` | **harus sama** dengan `media3_version` di `android/app/build.gradle` |
| `FFMPEG_BRANCH` | `release/6.0` | branch FFmpeg yang direkomendasikan Media3 1.11.1; boleh dinaikkan setelah diuji |
| `ANDROID_API` | `27` | sama dengan `minSdk`; tidak boleh lebih tinggi |
| `DECODERS` | `alac dca mlp truehd vorbis opus` | decoder FFmpeg yang diaktifkan |

Langkah yang dijalankan skrip:

1. Clone/checkout `androidx/media` pada `MEDIA3_TAG`.
2. Clone FFmpeg pada `FFMPEG_BRANCH` ke `libraries/decoder_ffmpeg/src/main/jni/ffmpeg`.
3. Jalankan `build_ffmpeg.sh` upstream (armeabi-v7a, arm64-v8a, x86, x86_64;
   x86 memakai `--disable-asm` sehingga tidak butuh nasm/yasm).
4. **License guard:** memeriksa `config.h` — `CONFIG_GPL`, `CONFIG_VERSION3`,
   `CONFIG_NONFREE` harus `0`, dan setiap decoder yang diminta harus aktif.
   Skrip berhenti jika tidak.
5. `./gradlew :libraries:decoder_ffmpeg:assembleRelease` (CMake/Ninja membangun
   `libffmpegJNI.so`, lalu dikemas ke AAR), hasilnya disalin ke
   `android/decoder-ffmpeg/libs/`.
6. Menulis bundle kepatuhan ke `build/ffmpeg-decoder-lgpl/`.

Status: skrip ini **belum dijalankan di workspace tanpa NDK/SDK**. Jalankan
sekali di devcontainer/CI, lalu commit AAR-nya.

## Wiring build

`android/settings.gradle` hanya `include ":decoder-ffmpeg"` bila AAR ada.
`android/app/build.gradle`:

- `implementation project(':decoder-ffmpeg')` hanya bila AAR ada;
- `BuildConfig.MEDIA3_FFMPEG_DECODER_LINKED` mengikuti keberadaan AAR;
- task `verifyFfmpegDecoderAar` membuat **build rilis gagal** bila AAR tidak ada,
  karena perangkat target tidak punya decoder ALAC platform yang bisa dipakai.
  Bypass sadar: `-PallowMissingFfmpegDecoder=true`
  (atau `ORG_GRADLE_PROJECT_allowMissingFfmpegDecoder=true` untuk Flutter).

`.github/workflows/android.yml` membangun AAR otomatis sebelum APK rilis bila AAR
belum ada di checkout (butuh NDK, diunduh lewat `sdkmanager` bila belum ada).

## Kewajiban lisensi (LGPL)

FFmpeg di dalam `libffmpegJNI.so` berlisensi LGPL v2.1+. Yang wajib dilakukan
untuk setiap APK yang didistribusikan:

1. Sertakan teks lisensi LGPL (`COPYING.LGPLv2.1`) dan Apache-2.0
   (`LICENSE.Apache-2.0`) di bundle notis aplikasi.
2. Publikasikan **sumber yang dipakai**: `ffmpeg-<branch>.tar.gz` dan
   `media3-decoder_ffmpeg-<tag>.tar.gz` dari bundle kepatuhan (lampirkan ke
   release GitHub, atau host permanen).
3. Sertakan `BUILD_INFO.txt` (revisi FFmpeg, decoder, NDK, checksum AAR) dan
   `android/build-ffmpeg-jni.sh` sebagai instruksi rebuild/relink.
4. Jangan menambahkan pembatasan yang melarang penerima memodifikasi/mengganti
   library tersebut (lihat §6 LGPL v2.1).

Ini bukan nasihat hukum — review hukum tetap disarankan sebelum rilis publik.
Yang jelas: tidak ada lagi komponen GPL yang memaksa seluruh aplikasi menjadi
GPLv3.

## Verifikasi

Log debug saat playback:

```
Ffmpeg: Renderer config: extensionRendererMode=PREFER decoderFallback=true
        moduleLinked=true available=true version=6.0 supported=ALAC,DTS,...
```

Dart: `PlaybackManager.ffmpegDecoderCapabilities` harus
`available=true, moduleLinked=true` dan `supportedCodecs` memuat `ALAC`.

- `moduleLinked=false` → AAR tidak ikut build (cek `MEDIA3_FFMPEG_DECODER_LINKED`).
- `moduleLinked=true, available=false` → `libffmpegJNI.so` gagal dimuat; cek
  `abiFilters`/arsitektur dan log `UnsatisfiedLinkError`.

Uji dengan file ALAC nyata di perangkat target (uninstall + install bersih, bukan
upgrade in-place).

## Update di masa depan

- Naikkan `media3_version` dan `MEDIA3_TAG` bersamaan, lalu rebuild AAR.
- Naikkan `FFMPEG_BRANCH` hanya setelah build + uji ALAC/DTS/TrueHD berhasil;
  guard `config.h` tetap menjaga postur LGPL.
- Jangan menambah kembali `org.jellyfin.media3:media3-ffmpeg-decoder` atau
  `ffmpeg_kit_flutter*` (proyek terakhir sudah diarsipkan 2025).

## Referensi

- Media3 FFmpeg extension: <https://github.com/androidx/media/tree/1.11.1/libraries/decoder_ffmpeg>
- FFmpeg legal: <https://www.ffmpeg.org/legal.html>
- LGPL v2.1: <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>
- Format media Android: <https://developer.android.com/media/platform/supported-formats>
