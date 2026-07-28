part of '../library_sections.dart';

class _LibraryItem {
  final String id;
  final IconData icon;
  final _LibraryDestination? destination;

  const _LibraryItem({required this.id, required this.icon, this.destination});
}

// Daftar default (urutan awal)
const _defaultItems = <_LibraryItem>[
  _LibraryItem(
    id: 'playlist',
    icon: CupertinoIcons.music_note_list,
    destination: _LibraryDestination.playlist,
  ),
  _LibraryItem(
    id: 'artist',
    icon: CupertinoIcons.mic,
    destination: _LibraryDestination.artists,
  ),
  _LibraryItem(
    id: 'album',
    icon: CupertinoIcons.square_stack,
    destination: _LibraryDestination.albums,
  ),
  _LibraryItem(
    id: 'songs',
    icon: CupertinoIcons.music_note,
    destination: _LibraryDestination.songs,
  ),
  _LibraryItem(id: 'tv', icon: CupertinoIcons.tv),
];

const _kOrderKey = 'library_item_order';

// ─── LibraryContent ────────────────────────────────────────────────────────────

enum _LibraryDestination { playlist, artists, albums, songs }
