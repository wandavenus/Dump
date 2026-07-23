/// Centralized navigation helper — eliminates string-based named routes
/// that produce invalid CSS selectors (`#/routename`) in web environments.
///
/// All push calls in the app should go through this class so that
/// [Navigator.pushNamed] is never used at the root [MaterialApp] level.
library;

import 'package:flutter/material.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/pages/settings_page.dart';
import 'package:musicplayer/utils/zoom_fade_route.dart';
import 'package:musicplayer/webView/web_view_container.dart';
import 'package:musicplayer/pages/album_page.dart';
import 'package:musicplayer/pages/artist_page.dart';
import 'package:musicplayer/pages/artist_list.dart';
import 'package:musicplayer/pages/music_list.dart';

abstract final class AppRouter {
  /// Push the Settings page on the root navigator so it overlays all tabs.
  static void pushSettings(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      ZoomFadeRoute(page: const SettingsPage()),
    );
  }

  /// Push the Album detail page on the nearest tab navigator.
  static void pushAlbum(
    BuildContext context, {
    required LocalSong album,
    required List<LocalSong> songs,
  }) {
    Navigator.of(context).push(
      ZoomFadeRoute(
        page: const WebView(child: AlbumPage()),
        settings: RouteSettings(
          name: 'album/${album.id}',
          arguments: {'album': album, 'songs': songs},
        ),
      ),
    );
  }

  /// Push the Artist detail page on the nearest tab navigator.
  static void pushArtist(BuildContext context, List<LocalSong> songs) {
    Navigator.of(context).push(
      ZoomFadeRoute(
        page: const WebView(child: ArtistPage()),
        settings: RouteSettings(
          name: 'artist/${songs.first.albumArtist ?? songs.first.artist}',
          arguments: songs,
        ),
      ),
    );
  }

  /// Push the Artist list page on the nearest tab navigator.
  static void pushArtistList(BuildContext context) {
    Navigator.of(context).push(
      ZoomFadeRoute(
        page: const WebView(child: ArtistList()),
        settings: const RouteSettings(name: 'artistlist'),
      ),
    );
  }

  /// Push the Music list page on the nearest tab navigator.
  static void pushMusicList(BuildContext context) {
    Navigator.of(context).push(
      ZoomFadeRoute(
        page: const WebView(child: MusicList()),
        settings: const RouteSettings(name: 'musiclist'),
      ),
    );
  }
}
