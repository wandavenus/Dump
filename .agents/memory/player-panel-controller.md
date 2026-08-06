---
name: PlayerPanelController adapter
description: PlayerPanelController adalah thin adapter; UnifiedMorphPlayer memakai PlayerSheetController sebagai backend state.
---

## Aturan
`lib/widgets/player/player_panel_controller.dart` hanya mendelegasikan ke `PlayerSheetController`. Jangan hapus `PlayerSheetController`; `UnifiedMorphPlayer` yang dipasang di `bottom_nav` masih menggunakannya sebagai sumber progress/expanded state.

**Why:** Widget `PlayerSheet` legacy telah dihapus, tetapi controller publiknya tetap menjadi kontrak state dan kontrol untuk MorphPlayer serta pemanggil service/settings.

**How to apply:** Semua widget baru (LocalSongCard, detail_sections, dsb.) memanggil `PlayerPanelController.instance.open()`. Jangan langsung import `PlayerSheetController` dari widget halaman.
