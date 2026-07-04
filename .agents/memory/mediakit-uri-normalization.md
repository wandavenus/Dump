---
name: MediaKit URI normalization
description: Media.normalizeURI() strips file:// prefix — all lookup keys must use raw path, not file:// URI
---

## Rule
`Media.normalizeURI('file:///sdcard/Music/song.mp3')` returns `'/sdcard/Music/song.mp3'` — raw filesystem path tanpa scheme. Jadi `Media.uri` selalu raw path.

**Impact**: Map yang di-key dengan `'file://${song.path}'` TIDAK PERNAH match `state.medias[i].uri`, sehingga semua lookup selalu return -1.

## How to apply
- `_uriToQueueIndex` keys: gunakan `song.path` (bukan `'file://${song.path}'`)
- Semua perbandingan dengan `nativeMedias[i].uri` atau `state.medias[i].uri`: gunakan `song.path` langsung
- `_buildMediaList`: tetap pakai `Media('file://${s.path}')` — benar untuk dikirim ke mpv, bukan untuk lookup

## Why
URIParser mendeteksi URIType.file dan memanggil `resource.toFilePath()` yang strip scheme. Ini terjadi di dalam konstruktor Media via normalizeURI. Setelah `setShuffle()`, media_kit rebuild list `current` dari `_getPlaylist` (mpv filename property = raw path) via `Media.new`, normalisasi yang sama berlaku sebelum dan sesudah shuffle.

## Consequence of getting it wrong
Playlist listener selalu "URI mismatch detected", return early, metadata tidak pernah update saat track berganti secara alami (shuffle maupun tidak). setTrack jump ke native index yang salah. _computeNextIndex jalur shuffle return -1 (fallback ke linear).
