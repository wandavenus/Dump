import 'podcast_episode.dart';

class PodcastShow {
  final String id;
  final String title;
  final String description;
  final String publisher;
  final String feedUrl;
  final String? artworkUrl;
  final List<PodcastEpisode> episodes;

  const PodcastShow({
    required this.id,
    required this.title,
    required this.description,
    required this.publisher,
    required this.feedUrl,
    this.artworkUrl,
    this.episodes = const [],
  });
}
