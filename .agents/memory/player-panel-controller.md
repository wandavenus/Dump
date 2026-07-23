---
name: PlayerPanelController adapter
description: PlayerPanelController adalah thin adapter; player UI asli tetap pakai stack lama (MiniPlayer + PlayerSheet + PlayerSheetController).
---

## Aturan
`lib/widgets/player/player_panel_controller.dart` hanya mendelegasikan ke `PlayerSheetController`. Jangan hapus `PlayerSheetController`, `player_sheet.dart`, atau `mini_player.dart` — ketiganya masih dipakai oleh `bottom_nav.dart`.

**Why:** Sesi sebelumnya merencanakan `ExpandablePlayerPanel` baru tapi file-nya tidak pernah dibuat. Agar tidak memecah player, dibuat adapter tipis sehingga kode baru bisa pakai `PlayerPanelController.instance.open()` tanpa harus mengubah implementasi player.

**How to apply:** Semua widget baru (LocalSongCard, detail_sections, dsb.) memanggil `PlayerPanelController.instance.open()`. Jangan langsung import `PlayerSheetController` dari widget halaman.
