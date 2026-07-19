# Regression Fix — Mini Player State Restoration

**Tanggal:** 18 Juli 2026  
**Versi:** 1.2.8  
**Regresi diintroduksi oleh:** Phase 8B Player Sheet Rendering Refactor

---

## Root Cause

### Mekanisme entry animation

`_buildMorph` menggunakan `_entryAnim` (AnimationController, range 0.0–1.0) untuk menganimasikan mini player dari bawah layar ke posisi normalnya:

```dart
final easedEntry = Curves.easeOutCubic.transform(_entryAnim.value);
final baseBottom = navBarH + safeBottom + miniBottomGap;
final entrySlide = (baseBottom + miniH) * (1.0 - easedEntry);
final bottom = lerpDouble(navBarH + safeBottom + miniBottomGap, 0.0, t)! - entrySlide;
```

Ketika `_entryAnim.value = 0.0`:
- `easedEntry = 0.0`
- `entrySlide = (baseBottom + miniH) ≈ 120px`
- `bottom = ~55px - 120px = -65px` → mini player berada **di bawah layar**, tidak terlihat

Ketika `_entryAnim.value = 1.0`:
- `easedEntry = 1.0`
- `entrySlide = 0`
- `bottom = navBarH + safeBottom` → posisi normal di atas nav bar

### Sebelum Phase 8B

`AudioService.playbackState` berada di dalam VLB chain di `build()`. Saat widget pertama kali di-build, VLB membaca `AudioService.playbackState.value` secara sinkron dan menampilkan lagu saat ini. Entry animation dipicu oleh `_onSongAppeared` yang merupakan listener terpisah — listener ini dipanggil setiap kali `playbackState` berubah, termasuk saat pertama kali listener di-attach (karena ada notifikasi awal dari native service).

### Setelah Phase 8B (regresi)

`initState()` mengisi `_currentSong` dari state saat ini dengan benar:

```dart
_currentSong = AudioService.playbackState.value.currentSong;
_isPlaying = AudioService.playbackState.value.isPlaying;
```

Karena `_currentSong` sudah non-null, `build()` tidak return `SizedBox.shrink()` — benar. **Tapi** `_entryAnim` tetap di nilai `0.0`.

Entry animation hanya dipicu di `_onPlaybackStateChanged` dengan kondisi:

```dart
if (_currentSong == null && song != null) {
  _entryAnim.forward(from: 0.0);
}
```

Setelah Activity recreation:
- Tidak ada perubahan song, isPlaying, atau position yang cukup untuk memicu notifikasi baru
- Bahkan jika notifikasi datang, `_currentSong` sudah non-null → kondisi `null → non-null` tidak terpenuhi
- `_entryAnim` tidak pernah maju → `entrySlide ≈ 120px` → mini player tersembunyi di bawah layar

**Inilah yang menyebabkan mini player tidak muncul setelah Activity recreation meski musik masih berjalan.**

---

## Changed Files

| File | Perubahan |
|---|---|
| `lib/widgets/unified_morph_player.dart` | Tambah `_entryAnim.value = 1.0` di `initState()` bila `_currentSong != null` |
| `lib/pages/settings_page/changelog_data.dart` | Tambah entry versi 1.2.8 |
| `pubspec.yaml` | Bump version ke 1.2.8+1 |

---

## Fix Description

Fix satu baris di `initState()` setelah inisialisasi `_currentSong`:

```dart
// Initialise fields from current state (in case widget mounts mid-playback,
// e.g. Activity recreation while Media3 is still playing).
_currentSong = AudioService.playbackState.value.currentSong;
_isPlaying = AudioService.playbackState.value.isPlaying;
// If a song is already active on mount (restored session / Activity recreation),
// jump the entry animation to its completed state so the mini player is
// immediately visible at the correct position.
// Without this, _entryAnim.value stays 0.0 → entrySlide = baseBottom + miniH
// → bottom becomes negative → mini player is hidden below the screen until
// the next playback event fires (which never comes if nothing changes).
if (_currentSong != null) {
  _entryAnim.value = 1.0;
}
```

### Mengapa ini benar

- **`_entryAnim.value = 1.0`** — bukan `forward()`. Tidak ada animasi, langsung jump ke posisi final. Ini benar karena saat Activity recreation, mini player seharusnya *langsung* terlihat tanpa slide-up animation (state sudah ada, bukan song baru).
- **`_entryAnim.forward(from: 0.0)`** di `_onPlaybackStateChanged` tetap dipertahankan untuk kasus normal: lagu pertama kali diputar dalam sesi baru → slide-up animation berjalan.
- **Tidak ada fake events**, tidak ada setState di initState, tidak ada playback notification yang dipicu.
- **Tidak mengubah rendering optimization Phase 8B** — VLB chain, listener scope, dan `_PlaybackContent` extraction semua tidak berubah.

### Matrix perilaku

| Kondisi | Sebelum fix | Sesudah fix |
|---|---|---|
| App fresh open, tidak ada lagu | `SizedBox.shrink()` | `SizedBox.shrink()` (tidak berubah) |
| Putar lagu pertama kali | `_entryAnim.forward()` via listener → slide-up | Sama (tidak berubah) |
| Background playback → kembali ke app | **Mini player tidak muncul** | `_entryAnim.value = 1.0` di initState → muncul langsung |
| Activity recreation (Back → buka lagi) | **Mini player tidak muncul** | `_entryAnim.value = 1.0` di initState → muncul langsung |
| Ganti lagu | setState via listener | Sama (tidak berubah) |
| Pause/Resume | setState via listener | Sama (tidak berubah) |
| Position tick 100ms | Diabaikan (Phase 8B opt) | Sama (tidak berubah) |

---

## Validation

### `flutter analyze`

```
Analyzing workspace...
No issues found! (ran in 10.4s)
```

✅ **Clean — 0 issues.**

### Phase 8B rendering optimizations

Semua optimasi Phase 8B tetap utuh:

- `AudioService.playbackState` **tidak** berada di VLB chain `build()`
- `_onPlaybackStateChanged` hanya `setState()` saat `song.id` atau `isPlaying` berubah
- Position tick diabaikan sepenuhnya di level `_UnifiedMorphPlayerState`
- `_PlaybackContent` widget masih menggunakan VLB-nya sendiri untuk isolasi position-tick rebuilds ke `PlayerContent` subtree saja
- `_buildMiniOverlay` dan artwork pulse masih pakai `_isPlaying` field bukan `state.isPlaying` parameter

### Mini Player restoration

- **Fresh playback:** `_currentSong == null` saat mount → `SizedBox.shrink()` → lagu dipilih → `_onPlaybackStateChanged` fires → `_currentSong = song`, `_entryAnim.forward()` → slide-up animation ✅
- **Background playback:** `_currentSong != null` saat mount → `_entryAnim.value = 1.0` → mini player langsung terlihat ✅
- **Activity recreation:** `_currentSong != null` saat mount → `_entryAnim.value = 1.0` → mini player langsung terlihat ✅
- **Song change:** `_onPlaybackStateChanged` deteksi `id` berbeda → `setState()` → rebuild dengan song baru ✅
- **Pause/Resume:** `_onPlaybackStateChanged` deteksi `isPlaying` berubah → `setState()` → ikon update ✅
- **Progress updates:** Tetap diabaikan di `_UnifiedMorphPlayerState`, ditangani oleh `_PlaybackContent` VLB ✅
