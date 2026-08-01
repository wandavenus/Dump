import 'package:flutter/material.dart';

import '../../extensions/localization_extension.dart';
import '../../models/local_song.dart';
import '../../theme/app_colors.dart';
import 'detail_sections.dart';

class ArtistPageContent extends StatelessWidget {
  const ArtistPageContent({super.key, required this.songs});

  final List<LocalSong> songs;

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 64.5;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArtistHero(songs: songs),
          PlayShuffleButtons(songs: songs),
          SongListSection(songs: songs),
          Divider(
            color: AppColors.of(context).subtleSeparator,
            thickness: 0.4,
            height: 1,
          ),
          _ArtistFooter(songs: songs),
          SizedBox(height: bottomClearance),
        ],
      ),
    );
  }
}

class _ArtistFooter extends StatelessWidget {
  const _ArtistFooter({required this.songs});

  final List<LocalSong> songs;

  String _formatTotalDuration(BuildContext context) {
    final l = context.l10n;
    final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    if (h > 0) return l.durationHoursMinutes(h, m);
    return l.durationOnlyMinutes(m);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final artistName = songs.first.artist;
    final albumCount = songs.map((s) => s.album).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            artistName,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.of(context).secondaryLabel,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.songsByArtist(songs.length, albumCount),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.of(context).secondaryLabel,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTotalDuration(context),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.of(context).secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}
