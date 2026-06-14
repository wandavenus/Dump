part of '../library_sections.dart';

class _LibraryItem {
  final String id;
  final IconData icon;
  final String title;
  final String? routeName;

  const _LibraryItem({
    required this.id,
    required this.icon,
    required this.title,
    this.routeName,
  });
}

// Daftar default (urutan awal)
const _defaultItems = <_LibraryItem>[
  _LibraryItem(id: 'playlist', icon: CupertinoIcons.music_note_list, title: 'Daftar Putar'),
  _LibraryItem(id: 'artist',   icon: CupertinoIcons.mic,             title: 'Artis'),
  _LibraryItem(id: 'album',    icon: CupertinoIcons.square_stack,    title: 'Album'),
  _LibraryItem(id: 'songs',    icon: CupertinoIcons.music_note,      title: 'Lagu',      routeName: '/musiclist'),
  _LibraryItem(id: 'tv',       icon: CupertinoIcons.tv,              title: 'TV & Film'),
];

const _kOrderKey = 'library_item_order';

// ─── LibraryContent ────────────────────────────────────────────────────────────
