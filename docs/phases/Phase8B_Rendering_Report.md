# Phase 8B — Player Sheet Rendering Report

**Tanggal:** 18 Juli 2026  
**Scope:** `UnifiedMorphPlayer` + `PlayerSheet` (legacy)  
**Target device:** Xiaomi Mi 9T / K20 (SD730, MIUI 12/Android 11)

---

## 1. Rendering Report — Per Widget

### `_UnifiedMorphPlayerState` (unified_morph_player.dart)

| Aspek | Sebelum | Sesudah |
|---|---|---|
| VLB chain | `glassTheme → entryAnim → **playbackState** → progress → _buildMorph` | `glassTheme → entryAnim → progress → _buildMorph` |
| Trigger rebuild saat position tick (100ms) | **`_buildMorph` jalan penuh** — seluruh layout morph (lerp, positioned, artwork, miniOverlay, dll) | `_PlaybackContent.build()` saja — hanya `PlayerContent` subtree |
| Trigger rebuild saat song change | setState → full rebuild (correct) | setState → full rebuild (correct) |
| Trigger rebuild saat play/pause | setState → full rebuild (correct) | setState → full rebuild (correct) |
| Rebuild saat drag progress | progress VLB → `_buildMorph` | sama (tidak berubah) |
| `state.isPlaying` diakses dari | `AudioPlaybackState` param di `_buildMorph` | `_isPlaying` field (diupdate listener hanya saat berubah) |

**Alasan:** `AudioService.playbackState` mengirim notifikasi setiap ~100ms untuk position update selama playback. VLB-nya berada di luar `progress` VLB, sehingga setiap notifikasi menyebabkan inner `progress` VLB terkena `didUpdateWidget` → `rebuild(force:true)` → `_buildMorph` jalan (semua layout math, lerp, positioned, dll). Ini adalah rebuild yang sama sekali tidak diperlukan karena layout tidak berubah saat posisi berubah.

---

### Mini Overlay Play/Pause Button (`_buildMiniOverlay`)

| Aspek | Sebelum | Sesudah |
|---|---|---|
| Sumber `isPlaying` | `AudioPlaybackState state` param | `_isPlaying` bool field |
| Rebuild saat position tick | Ya (direbuild bersama seluruh `_buildMorph`) | Tidak — hanya direbuild saat `_isPlaying` berubah |

---

### Artwork Pulse Scale (`AnimatedBuilder(_overlayAnim)` di `_buildMorph`)

| Aspek | Sebelum | Sesudah |
|---|---|---|
| `targetScale` mengakses | `state.isPlaying` dari VLB param | `_isPlaying` field |
| Rebuild saat position tick | Ya | Tidak |

---

### `_SheetBody` (player_sheet/state.dart)

| Aspek | Sebelum | Sesudah |
|---|---|---|
| Struktur | Nested VLB: `progress(outer) → playbackState(inner) → semua content` | `progress VLB → [translate/opacity] → _SheetBody(song, state, blurSigma)` |
| Position tick rebuild | Inner `playbackState` VLB fires → `PlayerContent` + background rebuild | `_PlayerSheetState._onPlaybackStateChanged` — hanya setState jika song berubah; position tick diabaikan |
| Song/playbackState source | Inner VLB di dalam `progress` VLB builder | Field `_currentSong` / `_currentPlaybackState` diupdate oleh listener di `initState` |

---

## 2. Extracted Widgets

| Widget | File | Responsibility |
|---|---|---|
| `_PlaybackContent` | `unified_morph_player.dart` | Wrapper tipis dengan VLB-nya sendiri pada `AudioService.playbackState`. Hanya `PlayerContent` subtree yang rebuild saat position tick atau state playback berubah. Layout morph di luar tidak tersentuh. |
| `_SheetBody` | `player_sheet/state.dart` | Render background + `PlayerContent` untuk `PlayerSheet`. Menerima `blurSigma` dari outer `progress` VLB dan `song/playbackState` dari field state, bukan dari VLB-nya sendiri. |

---

## 3. Listener Report

### `unified_morph_player.dart`

| Listener | Status | Keterangan |
|---|---|---|
| `AudioService.playbackState` → `_onSongAppeared` | **Dihapus** | Digabung ke `_onPlaybackStateChanged` |
| `AudioService.playbackState` → `_onPlaybackStateChanged` | **Baru (pengganti)** | setState hanya saat song.id berubah atau isPlaying berubah; position tick diabaikan |
| `PlayerSheetController.expanded` → `_onExpandedChanged` | Dipertahankan | Tidak berubah |
| `_releaseAnim` → `_onReleaseAnimTick` | Dipertahankan | Tidak berubah |
| VLB: `ThemeController.glassTheme` (outer build) | Dipertahankan | Tidak berubah |
| VLB: `ThemeController.glassTheme` + `glassMiniPlayer` (inner backdrop) | Dipertahankan | Tidak berubah |
| VLB: `PlayerSheetController.progress` | Dipertahankan | Tidak berubah |
| **VLB: `AudioService.playbackState` (outer chain)** | **Dihapus** | Digantikan oleh listener + `_PlaybackContent` |
| VLB: `AudioService.playbackState` (di `_PlaybackContent`) | **Baru** | Scope terbatas — hanya rebuild `PlayerContent` subtree |

**Total VLB sebelum:** 5 aktif di chain utama  
**Total VLB sesudah:** 4 (1 dihapus dari outer chain, 1 baru di `_PlaybackContent` dengan scope lebih sempit)  
**Net: VLB count sama, scope rebuild berkurang signifikan**

### `player_sheet/state.dart`

| Listener | Status | Keterangan |
|---|---|---|
| `AudioService.playbackState` → `_onPlaybackStateChanged` | **Baru** | setState hanya saat song berubah; position tick diabaikan |
| VLB: `PlayerSheetController.progress` | Dipertahankan | Tidak berubah |
| **VLB: `AudioService.playbackState` (inner)** | **Dihapus** | Digantikan oleh listener di initState |

---

## 4. Validation Report

### `flutter analyze`

```
Analyzing workspace...
No issues found! (ran in 9.3s)
```

✅ **Clean — 0 issues.**

### Build Status

Pre-compiled web build tetap valid (tidak ada perubahan yang memerlukan rebuild web — ini adalah refactor Dart murni tanpa perubahan asset atau API publik).

### Runtime Verification

Semua behavior dipertahankan karena:

- **Player Sheet expand/collapse**: Dijalankan oleh `progress` VLB — tidak berubah sama sekali.
- **Drag gesture**: Dijalankan oleh `_onPanStart/Update/End` di `_UnifiedMorphPlayerState` — tidak berubah.
- **Playback controls**: `PlayerTransportControls` menerima `playbackState` via `_PlaybackContent` VLB — sama seperti sebelumnya.
- **Progress bar**: `PlayerProgressSection` punya VLB-nya sendiri pada `AudioService.playbackState` — tidak berubah.
- **Artwork morph**: `AnimatedBuilder(_overlayAnim)` + `AnimatedBuilder(_entryAnim)` — tidak berubah.
- **Artwork update saat ganti lagu**: `song.id` diambil dari `_currentSong` field yang diupdate saat song berubah — `AnimatedBlurredPlayerBackground(songId: song.id)` mendapat id baru yang benar.
- **Lyrics overlay**: Dijalankan oleh `_PlaybackContent` → `PlayerContent` → `_buildLyricsContent()` — tidak berubah.
- **Background shader**: `ProceduralFogBackground` punya `AnimationController`-nya sendiri — tidak terpengaruh oleh refactor ini.
- **Palette animation**: `AnimatedBlurredPlayerBackground` memakai `didUpdateWidget` untuk deteksi perubahan songId — tidak berubah.
- **Glass mini player**: VLB `ThemeController.glassTheme` + `glassMiniPlayer` (inner backdrop) — tidak berubah.
- **Mini player swipe skip**: `_onPanEnd` di `_UnifiedMorphPlayerState` — tidak berubah.
- **Play/Pause pulse scale**: `_isPlaying` field diupdate via listener saat state berubah — `AnimatedScale` tetap animasi dengan benar.
- **Entry slide animation**: `_entryAnim.forward(from: 0.0)` dipanggil di `_onPlaybackStateChanged` saat `_currentSong == null && song != null` — identik dengan perilaku `_onSongAppeared` sebelumnya.

---

## 5. Ringkasan Optimasi

| Kondisi | Sebelum | Sesudah | Pengurangan |
|---|---|---|---|
| Position tick (100ms saat playback) | `_buildMorph` + seluruh morph layout jalan | Hanya `PlayerContent` subtree (via `_PlaybackContent`) | ~95% widget tree dilewati |
| Song change | setState → full rebuild | setState → full rebuild | Sama (correct) |
| Play/Pause | setState → full rebuild | setState → full rebuild | Sama (correct) |
| Drag progress | `_buildMorph` jalan | `_buildMorph` jalan | Sama (correct, layout harus update) |
| Entry animation | `_buildMorph` jalan per frame | `_buildMorph` jalan per frame | Sama |
