part of '../artist_list_sections.dart';

class _ArtistInfo {
  final String name;
  final List<LocalSong> songs;

  _ArtistInfo({required this.name, required this.songs});

  int get coverSongId => songs.first.id;
}
