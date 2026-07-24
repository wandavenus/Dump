---
name: Morph Player 60 FPS optimization
description: Penggantian semua implicit animation di jalur morph mini→full player; Ticker vsync di PlayerSheetController.
---

## Aturan

- **Jangan pernah pakai `AnimatedPositioned`, `AnimatedContainer`, `AnimatedOpacity`, `AnimatedScale`, `AnimatedPadding`, `AnimatedAlign` di jalur morph** (di dalam `content.dart`). Semua transisi visual harus pakai nilai langsung dari `PlayerSheetController.progress` + `lerpDouble`.
- **Overlay fade (showLyrics, showQueue, showOverlay, _lyricsExpand)** boleh memakai `TweenAnimationBuilder<double>` — ini explicit animation, bukan implicit. Polanya: `tween: Tween<double>(end: condition ? 1.0 : 0.0)` + `builder: (_, value, child) => Opacity(opacity: value, child: child)`. Duration/curve bebas sesuai kebutuhan visual.
- **Album cover** selalu pakai `Positioned` (fixed di posisi full-player) + `Transform.translate` + `Transform.scale` agar tidak ada relayout per frame. Layout size `largeCoverSize` konstan; transform menangani posisi visual.
- **`PlayerSheetController._animateTo()`** harus pakai `Ticker` (bukan `Timer.periodic`). `Ticker` di-create langsung: `Ticker(_onTick)`. Dispose wajib sebelum create baru + saat cancel. API publik tidak berubah: `setProgress()`, `open()`, `close()`, `toggle()`, `cancelAnimation()`.
- **Artwork** selalu decode di `largeCoverSize` — jangan pernah ganti `cacheWidth`/`size` saat drag.

**Why:** `AnimatedPositioned`/`AnimatedContainer` menambah 400ms implicit animation di atas nilai yang sudah dihitung dari progress → lag parah saat drag. `Timer.periodic` tidak sync vsync → frame drift. Transform menghindari layout pass per frame.

**How to apply:** Setiap kali ada perubahan di `content.dart` atau `player_sheet_controller.dart`, pastikan invariant di atas tetap terjaga.

## Lyrics expand/collapse fade
- Saat expand/collapse lirik, animasikan hanya opacity kontrol player; jangan mengubah mekanisme layout area lirik atau nilai `bottom` diskrit yang sudah menjadi bagian dari desain gesture.

**Why:** Desain aplikasi memang memakai expand/collapse untuk menyembunyikan atau menampilkan tombol player, bukan untuk menganimasikan pelebaran area lirik.

**How to apply:** Jika fade terasa kasar, ubah hanya durasi/curve pada `TweenAnimationBuilder` kontrol bawah; jangan memindahkan atau menginterpolasi `bottom` area lirik.
