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

## Rebuild scope (PERF-02/PERF-03)
- `PlayerContent` **tidak boleh** menerima `AudioPlaybackState`; ia hanya boleh bergantung pada song dan flag sub-view. `PlayerTransportControls` sekarang berlangganan `AudioService.playbackState` sendiri dan hanya `setState` saat `isPlaying`/`hasPlaylist` berubah.
- Nilai `PlayerSheetController.progress` dibaca oleh wrapper kecil (`_SheetProgressOpacity`, `_SheetProgressArtwork`), bukan oleh `PlayerContent.build`; child stabil dikirim lewat parameter `child` `ValueListenableBuilder`.
- `UnifiedMorphPlayer` membangun `PlayerContent` sekali per perubahan song/sub-view, lalu memakai instance yang sama di dalam builder progress.

**Why:** position tick (~100–200 ms) dan progress drag tidak boleh membangun ulang header/artwork/overlay yang tidak bergantung pada nilai tersebut.

**How to apply:** Jangan menambahkan `playbackState`, `PlayerSheetController.progress.value`, atau `ValueListenableBuilder` baru di `PlayerContent.build` tanpa mengukur build count. Regresi dijaga oleh `test/widgets/player_rebuild_scope_test.dart`.
