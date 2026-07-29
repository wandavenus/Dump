import 'dart:convert';
import 'dart:io';

import '../../models/podcast_episode.dart';
import '../../models/podcast_search_result.dart';
import '../../models/podcast_show.dart';
import 'podcast_provider.dart';

class RssPodcastProvider implements PodcastProvider {
  RssPodcastProvider({
    HttpClient? client,
    String? apiKey,
    String baseUrl = 'https://listen-api.listennotes.com/api/v2',
  })  : _client = client ?? HttpClient(),
        _apiKey = apiKey ??
            const String.fromEnvironment('LISTEN_NOTES_API_KEY') ??
            Platform.environment['LISTEN_NOTES_API_KEY'] ??
            '',
        _baseUrl = baseUrl {
    _client.autoUncompress = true;
  }

  final HttpClient _client;
  final String _apiKey;
  final String _baseUrl;

  @override
  Future<List<PodcastSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return _fetchPodcastResults(
        Uri.parse('$_baseUrl/best_podcasts?page=1'),
      );
    }

    final direct = Uri.tryParse(q);
    if (direct != null && direct.hasScheme) {
      return [
        PodcastSearchResult(
          id: direct.toString(),
          title: direct.host,
          publisher: direct.host,
          feedUrl: direct.toString(),
          description: 'Podcast feed URL',
        ),
      ];
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': q,
      'type': 'podcast',
      'only_in': 'title,author,description',
      'safe_mode': '1',
      'page_size': '20',
    });

    return _fetchPodcastResults(uri);
  }

  @override
  Future<PodcastShow> loadShow(PodcastSearchResult result) async {
    if (result.id.startsWith('http://') || result.id.startsWith('https://')) {
      throw UnsupportedError(
        'Direct RSS loading is not enabled in the Listen Notes provider.',
      );
    }

    final podcast = await _fetchPodcastJson(
      Uri.parse('$_baseUrl/podcasts/${Uri.encodeComponent(result.id)}'),
    );

    final title = _asString(
          podcast['title'],
        ) ??
        _asString(podcast['title_original']) ??
        result.title;

    final description = _strip(
      _asString(podcast['description']) ??
          _asString(podcast['description_original']) ??
          result.description ??
          '',
    );

    final publisher = _asString(
          podcast['publisher'],
        ) ??
        _asString(podcast['publisher_original']) ??
        result.publisher;

    final artwork = _asString(podcast['image']) ??
        _asString(podcast['thumbnail']) ??
        result.artworkUrl;

    final episodesJson = _asList(
          podcast['episodes'],
        ) ??
        const <dynamic>[];

    final episodes = <PodcastEpisode>[];
    for (final item in episodesJson) {
      if (item is! Map) continue;
      final episode = Map<String, dynamic>.from(item as Map);

      final audioUrl = _asString(episode['audio']);
      if (audioUrl == null || audioUrl.isEmpty) continue;

      final epTitle = _asString(episode['title']) ??
          _asString(episode['title_original']) ??
          'Untitled episode';

      episodes.add(
        PodcastEpisode(
          id: _asString(episode['id']) ?? audioUrl,
          showId: result.id,
          title: epTitle,
          description: _strip(
            _asString(episode['description']) ??
                _asString(episode['description_original']) ??
                '',
          ),
          audioUrl: audioUrl,
          artworkUrl:
              _asString(episode['image']) ?? _asString(episode['thumbnail']) ?? artwork,
          publishDate: _parsePublishedAt(
            _asInt(episode['pub_date_ms']) ??
                _asInt(episode['published_at_ms']) ??
                _asInt(episode['pub_date']),
          ),
          duration: _parseDurationSeconds(
            _asInt(episode['audio_length_sec']) ??
                _asInt(episode['audio_length']) ??
                _asInt(episode['duration_sec']) ??
                _asInt(episode['duration']),
          ),
        ),
      );
    }

    return PodcastShow(
      id: result.id,
      title: title,
      description: description,
      publisher: publisher,
      feedUrl: result.feedUrl,
      artworkUrl: artwork,
      episodes: episodes,
    );
  }

  Future<List<PodcastSearchResult>> _fetchPodcastResults(Uri uri) async {
    final json = await _fetchJson(uri);
    final items = _asList(json['results']) ??
        _asList(json['podcasts']) ??
        _asList(json['best_podcasts']) ??
        const <dynamic>[];

    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(_mapSearchResult)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  PodcastSearchResult _mapSearchResult(Map<String, dynamic> item) {
    final id = _asString(item['id']) ??
        _asString(item['listennotes_id']) ??
        _asString(item['podcast_id']) ??
        '';

    final title = _asString(item['title_original']) ??
        _asString(item['title']) ??
        _asString(item['title_highlighted']) ??
        id;

    final publisher = _asString(item['publisher_original']) ??
        _asString(item['publisher']) ??
        _asString(item['publisher_highlighted']) ??
        '';

    final description = _strip(
      _asString(item['description_original']) ??
          _asString(item['description']) ??
          _asString(item['description_highlighted']) ??
          '',
    );

    return PodcastSearchResult(
      id: id,
      title: title,
      publisher: publisher.isEmpty ? title : publisher,
      feedUrl: _asString(item['rss']) ?? '',
      description: description,
      artworkUrl: _asString(item['image']) ?? _asString(item['thumbnail']),
    );
  }

  Future<Map<String, dynamic>> _fetchPodcastJson(Uri uri) async {
    final response = await _request(uri);
    final decoded = jsonDecode(response) as Object?;
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON response from Listen Notes');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<String> _request(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_apiKey.isNotEmpty) {
      request.headers.set('X-ListenAPI-Key', _apiKey);
    }

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Listen Notes request failed: HTTP ${response.statusCode} for $uri\n$body',
        uri: uri,
      );
    }

    return body;
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static List<dynamic>? _asList(Object? value) {
    if (value is List) return value;
    return null;
  }

  static DateTime? _parsePublishedAt(int? ms) {
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }

  static Duration? _parseDurationSeconds(int? seconds) {
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  static String _strip(String s) {
    final decoded = _decode(s);
    return decoded.replaceAll(RegExp('<[^>]+>'), '').trim();
  }

  static String _decode(String s) {
    return s
        .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}
