---
name: CI versioning policy — Flutter SDK & Actions deliberately floating
description: Kebijakan versi di .github/workflows/ (keputusan eksplisit user, 8 Agustus 2026). Flutter SDK memakai channel:stable tanpa flutter-version (floating) dan semua GitHub Actions memakai major-tag floating — keduanya DISENGAJA, bukan kelalaian. Jangan "perbaiki" tanpa konfirmasi user. Yang wajib dipin (Gradle/JDK/NDK/SDK/media3) sudah ter-pin.
---

## Keputusan (8 Agustus 2026)

User memilih **Biarkan mengambang** untuk dua hal ini:

| Item | Kebijakan |
|---|---|
| Flutter SDK | `channel: stable` tanpa `flutter-version` — floating, selalu ikut stable terbaru |
| GitHub Actions | Major-tag floating (`actions/checkout@v7`, `setup-java@v5`, `gradle/actions/setup-gradle@v6`, `subosito/flutter-action@v2`, dll) — tanpa pin SHA/full-version |

Konsekuensi yang diterima user: build CI tidak 100% reproducible antar-rilis Flutter,
dan major-bump action (mis. checkout v7→v8) bisa bikin breaking tanpa disadari.
Audit berikutnya TIDAK perlu menyarankan pin `flutter-version` atau pin penuh action.

## Yang sudah dipin (jangan ubah tanpa alasan kuat)

- **Gradle** `9.6.1` — pin penuh di `android/gradle/wrapper/gradle-wrapper.properties`
- **JDK** temurin 21 — semua workflow (`kotlin.jvmToolchain(21)` di app/build.gradle)
- **NDK** `28.2.13676358` — pin di `android/app/build.gradle` (`ndkVersion`)
- **SDK level** compileSdk 36 / targetSdk 36 / minSdk 29 — pin di app/build.gradle
- **media3** `1.11.0` + **Jellyfin ffmpeg-decoder** `1.9.0+1` — pin di app/build.gradle (lihat `media3-1.11.0-migration.md`)
- **Dependencies Dart** — caret ranges di pubspec + `pubspec.lock` dikomit

## Catatan terkait

- **NDK cache** (8 Agustus 2026): `.github/workflows/android.yml` punya step
  `Cache Android NDK & CMake` (`actions/cache@v4`, path `/usr/local/lib/android/sdk/{ndk,cmake}`,
  key `runner.os}-android-ndk-` + hash `android/app/build.gradle`) — mencegah re-download
  NDK r28 ±1GB di runner GitHub tiap run.
- **Inkonsistensi kosmetik (diterima)**: `gradle/actions/setup-gradle@v6` di android.yml
  vs `@v4` di codeql.yml — user pilih biarkan.
- `gradle.properties` sudah optimal: `org.gradle.parallel=true`, `org.gradle.caching=true`,
  `org.gradle.jvmargs=-Xmx4G`, `android.enableR8.fullMode=true`, plus bypass AGP 9
  (`android.newDsl=false` + `android.builtInKotlin=false` — JANGAN dihapus berpasangan ini,
  lihat komentar di file).
