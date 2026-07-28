class PodcastEpisode {
  final String id;
  final String showId;
  final String title;
  final String description;
  final String audioUrl;
  final String? artworkUrl;
  final DateTime? publishDate;
  final Duration? duration;
  final String? localPath;

  const PodcastEpisode({
    required this.id,
    required this.showId,
    required this.title,
    required this.description,
    required this.audioUrl,
    this.artworkUrl,
    this.publishDate,
    this.duration,
    this.localPath,
  });

  PodcastEpisode copyWith({String? localPath}) => PodcastEpisode(
    id: id,
    showId: showId,
    title: title,
    description: description,
    audioUrl: audioUrl,
    artworkUrl: artworkUrl,
    publishDate: publishDate,
    duration: duration,
    localPath: localPath ?? this.localPath,
  );
}
