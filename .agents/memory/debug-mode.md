---
name: Debug mode activation
description: Mode debug diaktifkan dengan ketuk area Versi 3x dalam 2 detik; menampilkan section debug dengan status efek dan notif icon picker.
---

## Cara Aktivasi
- `_VersionTile` melacak tap count dan timestamp
- 3 tap dalam 2 detik → `_DebugState.enabled.value = true`
- Snackbar konfirmasi muncul
- Keluar: tap "Keluar Mode Debug" di section debug

## State
`_DebugState` adalah kelas in-memory (tidak persist antar session):
- `enabled: ValueNotifier<bool>` — toggle section debug
- `notifIcon: ValueNotifier<int>` — index ikon notifikasi (0-4)
- `notifIcons: List<({label, icon})}` — 5 opsi ikon

## Debug Section Contents
- Notifikasi icon picker
- Audio engine info (platform, effect support flags)
- Live effect status (spatial, normalize, bass boost, reverb, EQ, speed)
- Tombol keluar debug

**Why:** Fitur dev/testing yang perlu hidden dari user biasa; activation gesture yang tidak obvious (3 tap versi) adalah pola umum pada app mobile.
