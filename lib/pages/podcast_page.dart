import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_search_result.dart';
import '../models/podcast_show.dart';
import '../services/audio_service.dart';
import '../services/podcast/podcast_download_service.dart';
import '../services/podcast/podcast_provider.dart';
import '../services/podcast/rss_podcast_provider.dart';
import '../services/scroll_to_top_service.dart';
import '../themes/theme_controller.dart';
import '../widgets/common/scrolling_page_chrome.dart';

class PodcastPage extends StatefulWidget {
  const PodcastPage({super.key, this.provider});

  final PodcastProvider? provider;

  @override
  State<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends State<PodcastPage> {
  late final PodcastProvider _provider = widget.provider ?? RssPodcastProvider();

  final ScrollController _scroll = ScrollController();
  final TextEditingController _query = TextEditingController();

  double _scrollOffset = 0;
  bool _loading = true;
  String? _error;
  List<PodcastSearchResult> _results = const [];
  PodcastShow? _show;

  @override
  void initState() {
    super.initState();
    ScrollToTopService.signal(2).addListener(_onScrollToTop);
    unawaited(_search(''));
  }

  void _onScrollToTop() {
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
      _show = null;
    });

    try {
      final results = await _provider.search(query);
      if (!mounted) return;
      setState(() => _results = results);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadShow(PodcastSearchResult result) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final show = await _provider.loadShow(result);
      if (!mounted) return;
      setState(() => _show = show);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _play(PodcastEpisode episode) async {
    final local = await PodcastDownloadService.localPathFor(episode);
    final source = local ?? episode.audioUrl;

    final song = LocalSong(
      id: source.hashCode,
      title: episode.title,
      artist: _show?.publisher ?? 'Podcast',
      path: source,
      album: _show?.title ?? 'Podcast',
      albumId: (_show?.id ?? episode.showId).hashCode,
      artworkUri: episode.artworkUrl ?? _show?.artworkUrl,
      duration: episode.duration ?? Duration.zero,
      genre: 'Podcast',
    );

    await AudioService.playSongAt(
      playlist: [song],
      index: 0,
    );
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.axis == Axis.vertical) {
      final clamped = notification.metrics.pixels.clamp(0.0, 140.0);
      if (clamped != _scrollOffset) {
        setState(() => _scrollOffset = clamped);
      }
    }
    return false;
  }

  @override
  void dispose() {
    ScrollToTopService.signal(2).removeListener(_onScrollToTop);
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.glassTheme,
      builder: (context, isGlass, _) {
        final topPad =
            isGlass ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0.0;

        return Scaffold(
          extendBodyBehindAppBar: isGlass,
          appBar: FadingTitleAppBar(
            title: 'Podcast',
            scrollOffset: _scrollOffset,
          ),
          body: PrimaryScrollController(
            controller: _scroll,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScroll,
              child: Padding(
                padding: EdgeInsets.only(top: topPad),
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 80,
                  ),
                  children: [
                    const LargePageTitle(title: 'Podcast'),
                    const HeaderDivider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SearchBar(
                        controller: _query,
                        hintText: 'Cari podcast via Listen Notes atau paste RSS URL',
                        leading: const Icon(Icons.search),
                        onSubmitted: _search,
                        trailing: [
                          IconButton(
                            onPressed: () => _search(_query.text),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ],
                      ),
                    ),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      _Message(
                        icon: Icons.error_outline,
                        text: _error!,
                        action: () => _search(_query.text),
                      )
                    else if (_show == null)
                      _Results(
                        results: _results,
                        onTap: _loadShow,
                      )
                    else
                      _Show(
                        show: _show!,
                        onBack: () => setState(() => _show = null),
                        onPlay: _play,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.onTap,
  });

  final List<PodcastSearchResult> results;
  final ValueChanged<PodcastSearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const _Message(
        icon: Icons.podcasts,
        text: 'Podcast tidak ditemukan. Coba kata kunci lain atau paste RSS URL.',
      );
    }

    return Column(
      children: results
          .map(
            (r) => ListTile(
              leading: _Art(url: r.artworkUrl),
              title: Text(r.title),
              subtitle: Text(
                '${r.publisher}\n${r.description}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              onTap: () => onTap(r),
            ),
          )
          .toList(),
    );
  }
}

class _Show extends StatelessWidget {
  const _Show({
    required this.show,
    required this.onBack,
    required this.onPlay,
  });

  final PodcastShow show;
  final VoidCallback onBack;
  final ValueChanged<PodcastEpisode> onPlay;

  @override
  Widget build(BuildContext context) {
    if (show.episodes.isEmpty) {
      return _Message(
        icon: Icons.inbox_outlined,
        text: 'Episode belum tersedia.',
        action: onBack,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: _Art(url: show.artworkUrl, size: 72),
          title: Text(show.title),
          subtitle: Text(
            '${show.publisher}\n${show.description}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.close),
          ),
        ),
        ...show.episodes.map(
          (e) => _EpisodeTile(
            episode: e,
            onPlay: () => onPlay(e),
          ),
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.onPlay,
  });

  final PodcastEpisode episode;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, PodcastDownloadTask>>(
      valueListenable: PodcastDownloadService.tasks,
      builder: (context, tasks, _) {
        final task = tasks[episode.id];

        return ListTile(
          leading: _Art(url: episode.artworkUrl),
          title: Text(
            episode.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                episode.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (task?.isRunning ?? false)
                LinearProgressIndicator(
                  value: task!.progress == 0 ? null : task.progress,
                ),
              if (task?.error != null)
                TextButton(
                  onPressed: () => PodcastDownloadService.retry(episode),
                  child: const Text('Retry download'),
                ),
            ],
          ),
          isThreeLine: true,
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Play episode',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                tooltip: task?.isRunning ?? false
                    ? 'Cancel download'
                    : 'Download episode',
                onPressed: task?.isRunning ?? false
                    ? () => PodcastDownloadService.cancel(episode)
                    : () => PodcastDownloadService.download(episode),
                icon: Icon(
                  task?.localPath != null
                      ? Icons.download_done
                      : Icons.download_outlined,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({
    this.url,
    this.size = 56,
  });

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? const ColoredBox(
                color: Colors.black12,
                child: Icon(Icons.podcasts),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const Icon(Icons.podcasts),
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
          ),
          if (action != null)
            TextButton(
              onPressed: action,
              child: const Text('Coba lagi'),
            ),
        ],
      ),
    );
  }
}
