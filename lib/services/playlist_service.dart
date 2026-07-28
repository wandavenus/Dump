import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';

class PlaylistService {
  static const _playlistsKey = 'user_playlists';
  static const _favoritesKey = 'favorite_song_ids';

  // In-memory caches — avoids JSON decode on every read.  Both caches are
  // written through on every mutation so they stay in sync with SharedPrefs.
  static List<Playlist>? _cachedPlaylists;
  static List<int>? _cachedFavoriteIds;

  // ─── User Playlists ────────────────────────────────────────────────────────

  static Future<List<Playlist>> getPlaylists() async {
    if (_cachedPlaylists != null) return List.of(_cachedPlaylists!);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) {
      _cachedPlaylists = [];
      return [];
    }
    try {
      _cachedPlaylists = Playlist.decodeList(raw);
      return List.of(_cachedPlaylists!);
    } on Exception catch (_) {
      _cachedPlaylists = [];
      return [];
    }
  }

  static Future<void> _savePlaylists(List<Playlist> playlists) async {
    _cachedPlaylists = List.of(playlists); // write-through
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
    if (_cachedFavoriteIds != null) return List.of(_cachedFavoriteIds!);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) {
      _cachedFavoriteIds = [];
      return [];
    }
    try {
      _cachedFavoriteIds = (jsonDecode(raw) as List)
          .map((e) => e as int)
          .toList();
      return List.of(_cachedFavoriteIds!);
    } on Exception catch (_) {
      _cachedFavoriteIds = [];
      return [];
    }
  }

  static Future<bool> isFavorite(int songId) async {
    final ids = await getFavoriteIds();
    return ids.contains(songId);
  }

  static Future<bool> toggleFavorite(int songId) async {
    final ids = await getFavoriteIds();
    final isFav = ids.contains(songId);
    if (isFav) {
      ids.remove(songId);
    } else {
      ids.add(songId);
    }
    _cachedFavoriteIds = List.of(ids); // write-through
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoritesKey, jsonEncode(ids));
    return !isFav;
  }
}
