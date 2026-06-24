import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';

class PlaylistService {
  static const _playlistsKey = 'user_playlists';
  static const _favoritesKey = 'favorite_song_ids';

  // ─── User Playlists ────────────────────────────────────────────────────────

  static Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) return [];
    try {
      return Playlist.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, Playlist.encodeList(playlists));
  }

  static Future<Playlist> createPlaylist(String name) async {
    final playlists = await getPlaylists();
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      songIds: [],
      createdAt: DateTime.now(),
    );
    playlists.add(playlist);
    await _savePlaylists(playlists);
    return playlist;
  }

  static Future<void> deletePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _savePlaylists(playlists);
  }

  static Future<void> renamePlaylist(String id, String newName) async {
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    playlists[idx] = playlists[idx].copyWith(name: newName);
    await _savePlaylists(playlists);
  }

  static Future<void> addSong(String playlistId, int songId) async {
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final ids = List<int>.from(playlists[idx].songIds);
    if (!ids.contains(songId)) ids.add(songId);
    playlists[idx] = playlists[idx].copyWith(songIds: ids);
    await _savePlaylists(playlists);
  }

  static Future<void> removeSong(String playlistId, int songId) async {
    final playlists = await getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final ids = List<int>.from(playlists[idx].songIds)..remove(songId);
    playlists[idx] = playlists[idx].copyWith(songIds: ids);
    await _savePlaylists(playlists);
  }

  // ─── Favorites ─────────────────────────────────────────────────────────────

  static Future<List<int>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => e as int).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isFavorite(int songId) async {
    final ids = await getFavoriteIds();
    return ids.contains(songId);
  }

  static Future<bool> toggleFavorite(int songId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getFavoriteIds();
    final isFav = ids.contains(songId);
    if (isFav) {
      ids.remove(songId);
    } else {
      ids.add(songId);
    }
    await prefs.setString(_favoritesKey, jsonEncode(ids));
    return !isFav;
  }
}
