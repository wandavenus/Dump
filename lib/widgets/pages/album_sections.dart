import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../extensions/localization_extension.dart';
import '../../models/local_song.dart';
import '../../services/media_store_service.dart';
import '../../theme/app_colors.dart';
import '../song_artwork.dart';
import 'detail_sections.dart';

class AlbumPageContent extends StatelessWidget {
  const AlbumPageContent({
    super.key,
    required this.album,
    required this.songs,
  });

  final LocalSong album;
  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlbumHero(album: album),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs),
          _AlbumFooter(album: album, songs: songs),
          _MoreByArtist(currentAlbum: album),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _AlbumFooter extends StatelessWidget {
  const _AlbumFooter({required this.album, required this.songs});

  final LocalSong album;
  final List<LocalSong> songs;

  String _formatTotalDuration(BuildContext context) {
    final l = context.l10n;
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    if (h > 0) return l.durationHoursMinutes(h, m);
    return l.durationOnlyMinutes(m);
  }

  String _formatDate(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return DateFormat('d MMMM y', locale.toLanguageTag()).format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final year = album.year?.toString() ?? DateTime.now().year.toString();
    final artistName = album.albumArtist ?? album.artist;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(context),
            style: TextStyle(fontSize: 12, color: AppColors.of(context).secondaryLabel),
          ),
          const SizedBox(height: 2),
          Text(
            l.albumSongsAndDuration(songs.length, _formatTotalDuration(context)),
            style: TextStyle(fontSize: 12, color: AppColors.of(context).secondaryLabel),
          ),
          const SizedBox(height: 2),
          Text(
            '℗ $year $artistName',
            style: TextStyle(fontSize: 12, color: AppColors.of(context).secondaryLabel),
          ),
        ],
      ),
    );
  }
}

// ─── More by Artist ───────────────────────────────────────────────────────────

class _MoreByArtist extends StatefulWidget {
  const _MoreByArtist({required this.currentAlbum});

  final LocalSong currentAlbum;

  @override
  State<_MoreByArtist> createState() => _MoreByArtistState();
}

class _MoreByArtistState extends State<_MoreByArtist> {
  late Future<List<_AlbumGroup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadOtherAlbums();
    MediaStoreService.rescanNotifier.addListener(_onRescan);
  }

  void _onRescan() {
    if (!mounted) return;
    setState(() { _future = _loadOtherAlbums(); });
  }

  @override
  void dispose() {
    MediaStoreService.rescanNotifier.removeListener(_onRescan);
    super.dispose();
  }

  Future<List<_AlbumGroup>> _loadOtherAlbums() async {
    final allSongs = await MediaStoreService.getSongs();
    final artistName = widget.currentAlbum.albumArtist ?? widget.currentAlbum.artist;
    final currentAlbumName = widget.currentAlbum.album;

    // Filter songs: same artist, different album
    final artistSongs = allSongs.where((s) {
      final sArtist = s.albumArtist ?? s.artist;
      return (sArtist == artistName || s.artist == artistName) &&
          s.album != currentAlbumName;
    }).toList();

    // Group by album name
    final Map<String, List<LocalSong>> grouped = {};
    for (final s in artistSongs) {
      grouped.putIfAbsent(s.album, () => []).add(s);
    }

    return grouped.entries
        .map((e) => _AlbumGroup(name: e.key, songs: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final artistName =
        widget.currentAlbum.albumArtist ?? widget.currentAlbum.artist;

    return FutureBuilder<List<_AlbumGroup>>(
      future: _future,
      builder: (context, snapshot) {
        final albums = snapshot.data ?? [];
        if (albums.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: GestureDetector(
                onTap: () {
                  // Navigate to artist page
                  final artistSongs = albums
                      .expand((a) => a.songs)
                      .toList();
                  unawaited(Navigator.pushNamed(
                    context,
                    '/artist',
                    arguments: artistSongs,
                  ));
                },
                child: Row(
                  children: [
                    Text(
                      l.moreFromArtist(artistName),
                      style: TextStyle(
                        color: AppColors.of(context).primaryLabel,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.of(context).secondaryLabel,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),

            // Horizontal album cards
            SizedBox(
              height: 178,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16, right: 8),
                itemCount: albums.length,
                itemBuilder: (context, i) =>
                    _SmallAlbumCard(album: albums[i]),
              ),
            ),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─── Compact album card ────────────────────────────────────────────────────────

class _AlbumGroup {
  final String name;
  final List<LocalSong> songs;
  const _AlbumGroup({required this.name, required this.songs});
}

class _SmallAlbumCard extends StatelessWidget {
  const _SmallAlbumCard({required this.album});

  final _AlbumGroup album;

  @override
  Widget build(BuildContext context) {
    const double cardWidth = 130;
    const double artworkSize = 130;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/album',
        arguments: {
          'album': album.songs.first,
          'songs': album.songs,
        },
      ),
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork square with rounded corners
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SongArtwork(
                songId: album.songs.first.id,
                size: artworkSize,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 6),

            // Album title
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).primaryLabel,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),

            // Artist name
            Text(
              album.songs.first.albumArtist ?? album.songs.first.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
