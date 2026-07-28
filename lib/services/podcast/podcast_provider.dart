import '../../models/podcast_search_result.dart';
import '../../models/podcast_show.dart';

abstract class PodcastProvider {
  Future<List<PodcastSearchResult>> search(String query);
  Future<PodcastShow> loadShow(PodcastSearchResult result);
}
