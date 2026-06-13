import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../common/scrolling_page_chrome.dart';
import '../local_song_carousel.dart';
import '../song_artwork.dart';

class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          LargePageTitle(title: 'Beranda', align: false),
          HeaderDivider(),
          _LocalAlbumsSection(),
          SectionTitle(title: 'Recently Played', routeName: '/musiclist'),
          _RecentlyPlayedSection(),
          SectionTitle(title: 'Favourite Artists', routeName: '/artistlist'),
          _LocalArtistsSection(),
        ],
      ),
    );
  }
}

// ─── Data models ───────────────────────────────────────────────────────────────

class _AlbumGroup {
  final int albumId;
  final List<LocalSong> songs;

  _AlbumGroup({required this.albumId, required this.songs});

  String get name => songs.first.album;
  String get artist => songs.first.artist;
  int get coverSongId => songs.first.id;
}

class _ArtistGroup {
  final String name;
  final List<LocalSong> songs;

  _ArtistGroup({required this.name, required this.songs});

  int get coverSongId => songs.first.id;
}

// ─── Local Albums Section ─────────────────────────────────────────────────────

class _LocalAlbumsSection extends StatefulWidget {
  const _LocalAlbumsSection();

  @override
  State<_LocalAlbumsSection> createState() => _LocalAlbumsSectionState();
}

class _LocalAlbumsSectionState extends State<_LocalAlbumsSection> {
  List<_AlbumGroup> _albums = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final map = <int, List<LocalSong>>{};
      for (final song in songs) {
        map.putIfAbsent(song.albumId, () => []).add(song);
      }
      final albums = map.entries
          .map((e) => _AlbumGroup(albumId: e.key, songs: e.value))
          .toList();
      if (mounted) setState(() { _albums = albums; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 371,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 9),
          child: Text(
            'Top Picks For You',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 371,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            itemCount: _albums.length,
            itemBuilder: (context, index) => _AlbumCard(album: _albums[index]),
          ),
        ),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final _AlbumGroup album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/album',
        arguments: {'album': album.songs.first, 'songs': album.songs},
      ),
      child: Container(
        margin: const EdgeInsets.only(right: 10, left: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Album',
              style: TextStyle(
                color: Color.fromARGB(255, 153, 153, 153),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                ),
              ),
              child: SongArtwork(
                songId: album.coverSongId,
                size: 250,
                borderRadius: BorderRadius.zero,
              ),
            ),
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                height: 70,
                width: 250,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.fromARGB(255, 83, 83, 83),
                      Color.fromARGB(255, 36, 36, 36),
                    ],
                    stops: [0, 1],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 1)),
                    Text(
                      album.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(album.artist, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recently Played Section ──────────────────────────────────────────────────

class _RecentlyPlayedSection extends StatefulWidget {
  const _RecentlyPlayedSection();

  @override
  State<_RecentlyPlayedSection> createState() => _RecentlyPlayedSectionState();
}

class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
  List<LocalSong> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recentIds = await HistoryService.getRecentlyPlayedIds();
      final allSongs = await MediaStoreService.getSongs();
      final songMap = {for (final s in allSongs) s.id: s};
      final recent = recentIds
          .where(songMap.containsKey)
          .map((id) => songMap[id]!)
          .toList();
      if (mounted) setState(() { _songs = recent; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_songs.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(
          child: Text(
            'No recently played songs',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return LocalSongCarousel(songs: _songs);
  }
}

// ─── Local Artists Section ────────────────────────────────────────────────────

class _LocalArtistsSection extends StatefulWidget {
  const _LocalArtistsSection();

  @override
  State<_LocalArtistsSection> createState() => _LocalArtistsSectionState();
}

class _LocalArtistsSectionState extends State<_LocalArtistsSection> {
  List<_ArtistGroup> _artists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final songs = await MediaStoreService.getSongs();
      final playCounts = await HistoryService.getArtistPlayCounts();

      final artistMap = <String, List<LocalSong>>{};
      for (final song in songs) {
        artistMap.putIfAbsent(song.artist, () => []).add(song);
      }

      final artists = artistMap.entries
          .map((e) => _ArtistGroup(name: e.key, songs: e.value))
          .toList()
        ..sort((a, b) {
          final ca = (playCounts[a.name] as num?)?.toInt() ?? 0;
          final cb = (playCounts[b.name] as num?)?.toInt() ?? 0;
          return cb != ca ? cb.compareTo(ca) : a.name.compareTo(b.name);
        });

      if (mounted) setState(() { _artists = artists; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_artists.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _artists.length,
        itemBuilder: (context, index) => _ArtistCard(artist: _artists[index]),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final _ArtistGroup artist;

  const _ArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/artist', arguments: artist.songs),
      child: Container(
        margin: const EdgeInsets.only(top: 20, left: 15, bottom: 20),
        child: Column(
          children: [
            ClipPath(
              clipper: const ShapeBorderClipper(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(200)),
                ),
              ),
              child: SongArtwork(
                songId: artist.coverSongId,
                size: 150,
                borderRadius: BorderRadius.zero,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(artist.name, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 5),
                const Icon(Icons.star, color: Color.fromARGB(255, 255, 0, 0)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
