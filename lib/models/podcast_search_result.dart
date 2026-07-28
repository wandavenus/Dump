class PodcastSearchResult {
  final String id;
  final String title;
  final String publisher;
  final String feedUrl;
  final String? artworkUrl;
  final String description;

  const PodcastSearchResult({
    required this.id,
    required this.title,
    required this.publisher,
    required this.feedUrl,
    required this.description,
    this.artworkUrl,
  });
}
