---
name: LyricsService cascade
description: Urutan sumber lirik: embedded tag → .lrc same dir → .lrc folder → internet.
---

## Cascade Order
1. **Embedded tag** — `getEmbeddedLyrics(path)` via MethodChannel `musicplayer/media_store`; menggunakan jaudiotagger native; returns null/empty jika tidak ada
2. **Local .lrc same dir** — `{dirname(audioPath)}/{basenameWithoutExt}.lrc`
3. **Local .lrc configured folder** — `{AudioEffectsService.lyricsPath.value}/{basenameWithoutExt}.lrc`
4. **Internet** — `lrclib.net/api/search` dengan fallback normalize title/artist

## LyricsResult
```dart
class LyricsResult {
  final List<LyricLine> lines;
  final LyricsSource source; // embedded/localFile/internet/none
  String get sourceLabel; // "Dari tag file" / "Dari file .lrc" / "Dari internet" / ""
}
```

## API
```dart
await LyricsService.fetchLyrics(title: t, artist: a, filePath: p);
LyricsService.clearCache(); // panggil saat folder lirik berubah
```

## Web compat
`filePath` null → skip embedded & local, langsung internet. `kIsWeb` guard di embedded check.

**Why:** Urutan ini prioritaskan data lokal (lebih akurat, sync) sebelum internet. Embedded tag sering lebih sync dengan audio daripada .lrc dari internet.
