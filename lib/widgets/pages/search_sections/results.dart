part of '../search_sections.dart';

class _SearchResultsSliver extends StatelessWidget {
  final List<LocalSong> results;
  final List<LocalSong> allSongs;
  final String query;
  final List<OnlineTrack> onlineResults;
  final bool onlineLoading;

  const _SearchResultsSliver({
    required this.results,
    required this.allSongs,
    required this.query,
    required this.onlineResults,
    required this.onlineLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && onlineResults.isEmpty && !onlineLoading) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                color: AppColors.of(context).tertiaryLabel,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.searchNoResults(query),
                style: TextStyle(
                  color: AppColors.of(context).secondaryLabel,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[
      if (results.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Local Songs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      for (final song in results)
        _SearchResultTile(
          song: song,
          playlist: allSongs,
          index: allSongs.contains(song) ? allSongs.indexOf(song) : 0,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          'Online Results',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (onlineLoading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        )
      else if (onlineResults.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No online results from installed extensions.',
            style: TextStyle(color: AppColors.of(context).secondaryLabel),
          ),
        )
      else
        for (final track in onlineResults) _OnlineTrackTile(track: track),
    ];
    return SliverList(delegate: SliverChildListDelegate(children));
  }
}

class _OnlineTrackTile extends StatelessWidget {
  const _OnlineTrackTile({required this.track});
  final OnlineTrack track;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: track.artwork == null
          ? const Icon(Icons.cloud_download)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                track.artwork!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
      title: Text(track.title),
      subtitle: Text(
        '${track.artist} • ${track.album}${track.quality == null ? '' : ' • ${track.quality}'}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download_rounded),
        onPressed: () {
          DownloadManager.instance.enqueue(track);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Queued ${track.title}')));
        },
      ),
    );
  }
}
