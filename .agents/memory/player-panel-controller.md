---
name: PlayerPanelController adapter
description: PlayerPanelController adalah thin adapter; player UI asli tetap pakai stack lama (MiniPlayer + PlayerSheet + PlayerSheetController).
---

## Aturan
`lib/widgets/player/player_panel_controller.dart` hanya mendelegasikan ke `PlayerSheetController`. Jangan hapus `PlayerSheetController`, `player_sheet.dart`, atau `mini_player.dart` tanpa audit dependensi; `UnifiedMorphPlayer` kini menjadi widget player yang dipasang di `bottom_nav`, sementara `PlayerSheet` tersisa sebagai implementasi legacy.

**Why:** `UnifiedMorphPlayer` menggantikan pemasangan langsung stack lama di `bottom_nav`, tetapi controller dan file legacy masih menjadi bagian dari kompatibilitas internal serta referensi widget lain.

**How to apply:** Semua widget baru (LocalSongCard, detail_sections, dsb.) memanggil `PlayerPanelController.instance.open()`. Jangan langsung import `PlayerSheetController` dari widget halaman.
