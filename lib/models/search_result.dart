import 'local_song.dart';
import 'online_album.dart';
import 'online_artist.dart';
import 'online_track.dart';

enum SearchResultType { localSong, onlineTrack, onlineAlbum, onlineArtist, onlinePlaylist }

class SearchResult {
  final SearchResultType type;
  final LocalSong? localSong;
  final OnlineTrack? onlineTrack;
  final OnlineAlbum? album;
  final OnlineArtist? artist;

  const SearchResult._({
    required this.type,
    this.localSong,
    this.onlineTrack,
    this.album,
    this.artist,
  });

  const SearchResult.local(LocalSong song)
      : this._(type: SearchResultType.localSong, localSong: song);

  const SearchResult.track(OnlineTrack track)
      : this._(type: SearchResultType.onlineTrack, onlineTrack: track);

  const SearchResult.album(OnlineAlbum album)
      : this._(type: SearchResultType.onlineAlbum, album: album);

  const SearchResult.artist(OnlineArtist artist)
      : this._(type: SearchResultType.onlineArtist, artist: artist);

  String get title => switch (type) {
        SearchResultType.localSong => localSong?.title ?? '',
        SearchResultType.onlineTrack => onlineTrack?.name ?? '',
        SearchResultType.onlineAlbum => album?.name ?? '',
        SearchResultType.onlineArtist => artist?.name ?? '',
        SearchResultType.onlinePlaylist => '',
      };

  String get subtitle => switch (type) {
        SearchResultType.localSong => localSong?.artist ?? '',
        SearchResultType.onlineTrack => onlineTrack?.artistName ?? '',
        SearchResultType.onlineAlbum => album?.artistName ?? '',
        SearchResultType.onlineArtist => artist?.description ?? '',
        SearchResultType.onlinePlaylist => '',
      };

  String? get coverUrl => switch (type) {
        SearchResultType.localSong => localSong?.artworkUri,
        SearchResultType.onlineTrack => onlineTrack?.coverUrl,
        SearchResultType.onlineAlbum => album?.coverUrl,
        SearchResultType.onlineArtist => artist?.imageUrl,
        SearchResultType.onlinePlaylist => null,
      };
}
