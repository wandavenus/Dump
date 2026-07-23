part of '../artist_list_sections.dart';

class ArtistInfo {
  final String name;
  final List<LocalSong> songs;

  ArtistInfo({required this.name, required this.songs});

  int get coverSongId => songs.first.id;
}
