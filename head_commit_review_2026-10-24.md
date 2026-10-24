# Review diff HEAD — `b622c84`

Tanggal: 24 Oktober 2026  
Base: `HEAD^` (`999ba416`)  
Commit: `feat: wire native AutoMix fade path`

## Ringkasan

Review mencakup seluruh 15 file pada diff `HEAD^..HEAD`, terutama wiring
Media3/Kotlin, processor PCM native C/JNI, test, build hook, changelog, dan
dokumentasi. Ditemukan tiga isu yang perlu diperbaiki sebelum jalur native fade
dianggap aman untuk release.

## Temuan

### P1 — Timeline native fade salah ketika Signalsmith Stretch aktif

**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:1521-1558`
- `native_audio_runtime/src/automix_fade_processor.c:338-363`

`AutomixFadeAudioProcessor` ditempatkan **setelah** `SignalsmithStretch`, tetapi
`nar_automix_fade_arm()` mengubah `start_position_ms` dan `duration_ms` menjadi
frame memakai `sample_rate` biasa. Processor fade menghitung frame PCM output,
sedangkan `SignalsmithStretch` menghasilkan `inputFrames / playbackRate` output
frames. `currentPosition` sendiri sudah dikoreksi kembali ke media timeline oleh
`StretchAwareAudioProcessorChain`.

Akibatnya, setiap playback speed atau AutoMix tempo multiplier selain 1.0 dapat
menggeser fase fade. Contoh pada 2.0x: 60 detik media hanya menjadi sekitar 30
detik frame output, tetapi anchor native dikonversi sebagai 60 detik frame;
clamp cursor kemudian menunda envelope sekitar 30 detik output. Pada 0.5x,
anchor dapat langsung ter-clamp ke cursor dan durasi fade menjadi tidak sesuai.

**Perbaikan minimum:** gunakan anchor/durasi dalam output-frame timeline yang
disediakan atau disinkronkan dengan processor Stretch, lalu konversi media-time
ke output-frame berdasarkan rasio aktual yang sama. Memindahkan processor saja
tidak cukup tanpa menetapkan kontrak timeline yang benar.

### P1 — Partial arm tidak di-rollback dan dapat menggandakan envelope

**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/effects/AutomixFadeAudioProcessor.kt:364-382`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:696-700`

`AutomixFadeManager.arm()` meng-arm deck outgoing lebih dulu, kemudian incoming,
lalu hanya mengembalikan `outgoingArmed && incomingArmed`. Bila arm incoming
gagal setelah outgoing berhasil (misalnya satu slot sudah `failed` setelah JNI
atau processor error), plan outgoing tetap aktif. Controller hanya memanggil
`resetAutoMixCrossfade()` bila `nativeFadeArmed` bernilai `true`; pada partial
failure nilainya `false`, sehingga tidak ada cleanup.

Controller lalu memakai fallback `Player.volume` untuk kedua deck, sementara
satu deck masih menerima gain native. Dampaknya adalah double fade, envelope
stale pada transisi berikutnya, dan pelanggaran kontrak fail-open.

**Perbaikan minimum:** buat `arm()` atomik secara logis dengan me-reset kedua
slot bila salah satu arm gagal, dan/atau ubah controller agar selalu me-reset
kedua deck setiap `nativeFadeAvailable == false`, bukan hanya ketika arm penuh
berhasil.

### P2 — Seek saat native crossfade hanya memindahkan timeline deck aktif

**Lokasi:**

- `android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt:2007-2013`
- `android/app/src/main/kotlin/dev/wndavenz/music/crossfade/CrossfadeController.kt:1201-1227`

Saat crossfade berlangsung, `activePlayer` adalah incoming deck, sedangkan
outgoing deck masih memutar audio. Callback seek hanya memanggil
`setTimelinePosition()` untuk player `p` yang aktif. Pada block audio berikutnya,
timeline update itu dapat membatalkan plan native incoming, tetapi plan native
outgoing tetap hidup. Controller masih menganggap native fade aktif dan menulis
volume master penuh ke kedua player, sehingga kedua deck tidak lagi memakai
envelope yang sama setelah seek.

**Perbaikan minimum:** batalkan crossfade sebelum seek, atau reset/rearm kedua
slot dan paksa fallback Kotlin ketika terjadi seek/discontinuity selama overlap.

## Checks

Lulus:

- `git diff --check HEAD^ HEAD`
- `./gradlew :app:testDebugUnitTest --no-daemon`
- `dart analyze lib test`
- `dart test` dari `native_audio_runtime`
- Host AutoMix C suite yang dikompilasi dari source HEAD dengan Clang
- Host AutoMix C suite dengan AddressSanitizer + UndefinedBehaviorSanitizer
- Syntax check `automix_fade_processor.c` dengan Clang

Kotlin test suite lulus dengan warning existing/deprecation Gradle dan satu
warning Kotlin existing di `Media3PlaybackService.kt:2387` (`Condition is always
'true'`). Tidak ada fresh-install atau playback fisik pada Xiaomi Mi 9T/Redmi K20
yang bisa memvalidasi hasil audible/AudioTrack.

## Kesimpulan

Commit ini berhasil dikompilasi dan test yang tersedia lulus, tetapi belum siap
dianggap memenuhi kontrak native sample-timeline fade karena timeline belum
memperhitungkan Stretch dan jalur fallback masih dapat meninggalkan plan native
parsial. Perbaiki dua temuan P1 terlebih dahulu; temuan seek perlu ditutup
sebelum mengandalkan native fade pada interaksi transport selama overlap.
