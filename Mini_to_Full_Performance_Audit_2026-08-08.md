# Mini → Full Player Performance Audit

Date: 2026-08-08  
Scope: `UnifiedMorphPlayer` drag/release path  
Target: Xiaomi Mi 9T/K20, Snapdragon 730, Android 11 / MIUI 12

## Kesimpulan singkat

Ada beberapa beban yang benar-benar terjadi bersamaan saat `progress` berubah. Penyebab paling kuat dari frame drop adalah:

1. full-player subtree ikut dibuild ulang melalui `ValueListenableBuilder<double>` setiap perubahan `progress`;
2. full-player subtree dianimasikan dengan `Opacity` selama `fullAlpha` masuk dari 0 ke 1, yang dapat memerlukan compositing/offscreen layer untuk area besar;
3. animated artwork memakai `BoxShadow` yang blur radius dan opacity-nya berubah mengikuti progress;
4. procedural fragment shader tetap berjalan setiap frame bersamaan dengan morph;
5. pada rentang tertentu, beberapa layer besar aktif sekaligus: background shader, gradient overlay, full player, mini overlay, dan artwork shadow.

Tidak ada bukti dari kode saja bahwa satu kandidat tertentu adalah penyebab tunggal. Web preview saat audit memakai CPU-only rendering (`webGLVersion is -1`), sehingga tidak dipakai sebagai bukti GPU Android.

## Bukti langsung dari kode

### 1. Seluruh `_buildMorph` berjalan setiap perubahan progress

`UnifiedMorphPlayer.build()` memasang `ValueListenableBuilder<double>` pada `PlayerSheetController.progress`, lalu langsung memanggil `_buildMorph(...)`.

Di sisi gesture, `_onPanUpdate()` memanggil `PlayerSheetController.setProgress(...)` untuk setiap update vertikal. `setProgress()` selalu menulis `progress.value`; tidak ada guard untuk menggabungkan update yang datang lebih dari sekali dalam satu frame.

**Dampak yang dapat dipastikan:**

- seluruh fungsi `_buildMorph` dijalankan berulang selama drag;
- object Dart seperti `Positioned`, `Opacity`, `Transform`, `BoxDecoration`, `Border`, `Offset`, dan nilai interpolasi dibuat ulang;
- child state biasanya tetap dipertahankan oleh Flutter, tetapi build/layout/compositing decision tetap perlu dievaluasi ulang.

**Kepastian:** tinggi untuk rebuild; belum cukup untuk menyimpulkan durasi frame tanpa trace UI thread.

### 2. Full player baru aktif di tengah morph dan dibungkus Opacity + Transform

Rentang:

- `fullAlpha = ((progress - 0.12) / 0.38).clamp(0.0, 1.0)`;
- full player mulai masuk pada `progress > 0.12`;
- `_PlaybackContent` dibungkus `Transform.translate` dan `Opacity`.

`_PlaybackContent` berisi `PlayerContent`, yang merupakan subtree besar dengan `LayoutBuilder`, `Column`, beberapa `Positioned`, kontrol player, lyrics/queue area, dan `TweenAnimationBuilder`.

**Dampak yang dapat dipastikan:**

- pada fase `0.12–0.50`, subtree full player berada dalam transisi opacity;
- opacity non-trivial pada subtree besar dapat memerlukan compositing layer/offscreen buffer;
- `Transform.translate` menggerakkan keseluruhan subtree, sehingga layer besar tersebut juga harus dikomposisikan ulang saat bergerak;
- parent `_buildMorph` membuat instance widget `_PlaybackContent` baru pada setiap progress tick, walaupun element/state biasanya direuse.

**Kepastian:** tinggi bahwa compositing dan rebuild terjadi; biaya aktual perlu dilihat di raster/UI timeline.

### 3. Artwork morph memiliki BoxShadow yang dianimasikan setiap frame

Pada artwork utama di `unified_morph_player.dart`, `BoxDecoration.boxShadow` memakai:

- alpha `0.10 * progress`;
- `blurRadius: 1 * progress`;
- `spreadRadius: 0.1 * progress`;
- offset Y `1 * progress`.

Shadow ini berada di container artwork besar yang juga berubah ukuran secara visual melalui `Transform.scale`.

**Dampak yang dapat dipastikan:**

- parameter blur berubah selama setiap morph;
- artwork tetap berada dalam jalur paint/compositing morph;
- shadow bukan lagi shadow mini player yang sudah dihapus, melainkan shadow artwork full/morph.

**Kepastian:** tinggi sebagai pekerjaan paint/compositing tambahan. Apakah cukup untuk menyebabkan drop harus diukur.

### 4. Procedural shader berjalan bersamaan dengan drag morph

Saat `bgAlpha > 0` (`progress > 0`), `AnimatedBlurredPlayerBackground` dipasang. `ProceduralFogBackground` membuat `AnimationController` 30 menit yang terus `repeat()` dan memberi `CustomPainter` repaint pada setiap tick.

Shader dirender pada target 256×512 lalu di-upscale melalui `FittedBox`. RepaintBoundary mengisolasi repaint shader, tetapi tidak menghapus biaya GPU shader atau compositing opacity di parent.

**Dampak yang dapat dipastikan:**

- selama sheet dibuka/bergerak, ada ticker shader yang aktif selain ticker morph;
- shader melakukan paint sendiri setiap frame;
- background juga dibungkus `Opacity(opacity: bgAlpha)` pada awal morph;
- ada gradient overlay kedua yang juga dibungkus opacity.

**Kepastian:** tinggi bahwa shader aktif bersamaan; biaya aktual tergantung GPU/driver dan harus diprofilkan di perangkat target.

### 5. Beberapa layer besar overlap pada rentang yang sama

Rentang overlap paling berat secara struktur:

- `0.00–0.12`: background shader + gradient overlay + morph artwork + mini overlay;
- `0.12–0.28`: semua di atas + full player opacity masuk + artwork shadow;
- `0.28–0.35`: background masih opacity transition, full player, artwork shadow;
- `0.35–0.50`: background sudah penuh, full player masih opacity transition, artwork shadow;
- `0.50–1.00`: full player + background shader + artwork morph/shadow.

Pada `0.12–0.28`, mini overlay belum selesai fade out sementara full player sudah mulai fade in. Ini adalah fase yang paling layak diuji lebih dulu.

**Kepastian:** tinggi berdasarkan formula opacity dan conditional widget.

### 6. BackdropFilter glass mini player bukan kandidat utama sepanjang drag, tetapi ada spike di awal

Glass mini player memakai `BackdropFilter(ImageFilter.blur(sigmaX: 24, sigmaY: 24))`, tetapi kode hanya mengaktifkannya bila `progress < 0.02`.

Ini membatasi dampak ke awal gesture. Namun pada perangkat yang lambat, perubahan dari kondisi idle ke gesture terjadi tepat ketika layer backdrop masih aktif, dan RepaintBoundary tidak menghilangkan biaya recomposite backdrop yang berubah.

**Kepastian:** tinggi bahwa filter aktif pada window `0–0.02`; rendah bahwa ini penyebab utama seluruh mini→full drop.

## Kandidat yang diperiksa tetapi bukan bukti penyebab utama

### Controller dan release animation

`PlayerSheetController` memakai `Ticker`, bukan `Timer.periodic`, dan `_releaseAnim` juga memakai `AnimationController`. Ini sudah vsync-driven untuk animasi setelah jari dilepas.

Namun drag langsung tetap menulis notifier dari `_onPanUpdate()`. Event pointer tidak dijamin satu-per-satu bertepatan dengan vsync. Ini membuat update berlebih mungkin terjadi, tetapi perlu trace untuk membuktikan apakah UI thread menerima lebih dari satu rebuild per frame.

### Artwork decode

`SongArtwork` memakai cache/provider dan `largeCoverSize` tetap selama morph. Tidak terlihat perubahan `cacheWidth` per frame atau decode baru yang dipicu oleh perubahan ukuran. Decode ulang bukan kandidat utama berdasarkan kode ini.

### `AnimatedScale`

Ada `AnimatedScale` di sekitar artwork morph, tetapi targetnya bergantung pada `overlayT` dan `_isPlaying`, bukan `progress` biasa. Pada drag mini→full normal, target umumnya tidak berubah. Ia tetap merupakan implicit animation di jalur artwork dan perlu dipertahankan sebagai kandidat arsitektur, tetapi belum terbukti sebagai sumber drop untuk gesture ini.

### Karaoke painter

Karaoke painter hanya relevan saat lyrics view aktif. Ia bukan bagian dari jalur mini→full normal ketika lyrics/queue tidak sedang dibuka.

## Prioritas verifikasi di perangkat target

Urutan A/B profiling yang disarankan:

1. Profile release/profile build di Mi 9T/K20, bukan web preview.
2. Rekam satu gesture mini→full dengan Flutter DevTools Performance dan aktifkan raster stats.
3. Bandingkan frame timeline dengan shader background dinonaktifkan sementara.
4. Bandingkan lagi dengan artwork `BoxShadow` dinonaktifkan sementara.
5. Bandingkan dengan full-player opacity transition diganti tanpa opacity layer besar.
6. Periksa apakah spike dominan di UI thread (build/layout) atau raster thread (paint/compositing/GPU).
7. Ukur fase progress `0.12–0.28` secara terpisah karena di sana mini overlay dan full player overlap.

Interpretasi:

- UI thread tinggi → fokus pada rebuild `PlayerContent`, object churn, dan update progress yang tidak dibatasi vsync.
- Raster/GPU tinggi → fokus pada shader, artwork BoxShadow, opacity saveLayer, clip, dan overlap layer.
- Keduanya tinggi → kurangi overlap dulu, lalu pisahkan full-player build dari progress-driven shell.

## Kesimpulan audit

Kode menunjukkan bahwa frame drop bukan sekadar dugaan dari shadow mini player yang sudah dihapus. Shadow mini player memang sudah tidak ada. Beban paling konkret sekarang adalah kombinasi:

`progress rebuild → full subtree build/layout → large opacity/transform composite + shader repaint + animated artwork shadow`.

Tanpa profile trace dari Mi 9T/K20, tidak benar untuk mengklaim satu komponen sebagai root cause tunggal. Tetapi kandidat di atas cukup konkret untuk A/B profiling terarah dan tidak memerlukan tebakan visual.