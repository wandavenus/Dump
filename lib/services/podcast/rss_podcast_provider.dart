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
        _apiKey = _resolveApiKey(apiKey),
        _baseUrl = baseUrl {
    _client.autoUncompress = true;
  }

  final HttpClient _client;
  final String _apiKey;
  final String _baseUrl;

  static String _resolveApiKey(String? apiKey) {
    final envKey = const String.fromEnvironment('LISTEN_NOTES_API_KEY');
    return (apiKey ?? envKey).trim();
  }

  @override
  Future<List<PodcastSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return _fetchPodcastResults(
        Uri.parse('$_baseUrl/best_podcasts?page=1'),
      );
    }

    final direct = Uri.tryParse(q);
    if (direct != null &&
        direct.hasScheme &&
        (direct.scheme == 'http' || direct.scheme == 'https')) {
      return [
        PodcastSearchResult(
          id: q,
          title: direct.host.isEmpty ? 'Podcast feed' : direct.host,
          publisher: direct.host.isEmpty ? 'Podcast feed' : direct.host,
          feedUrl: q,
          description: 'RSS podcast feed',
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
    final feedUrl = result.feedUrl.trim();
    final id = result.id.trim();

    if (_looksLikeUrl(id) || _looksLikeUrl(feedUrl)) {
      return _loadFromRss(
        feedUrl.isNotEmpty ? feedUrl : id,
        fallback: result,
      );
    }

    return _loadFromListenNotes(result);
  }

  Future<PodcastShow> _loadFromListenNotes(PodcastSearchResult result) async {
    final podcast = await _fetchJson(
      Uri.parse('$_baseUrl/podcasts/${Uri.encodeComponent(result.id)}'),
    );

    final title = _asString(podcast['title']) ??
        _asString(podcast['title_original']) ??
        result.title;

    final description = _strip(
      _asString(podcast['description']) ??
          _asString(podcast['description_original']) ??
          result.description,
    );

    final publisher = _asString(podcast['publisher']) ??
        _asString(podcast['publisher_original']) ??
        result.publisher;

    final artwork = _asString(podcast['image']) ??
        _asString(podcast['thumbnail']) ??
        result.artworkUrl;

    final episodes = await _loadEpisodesForPodcast(result.id, podcast);

    return PodcastShow(
      id: result.id,
      title: title,
      description: description,
      publisher: publisher,
      feedUrl: _asString(podcast['rss']) ?? result.feedUrl,
      artworkUrl: artwork,
      episodes: episodes,
    );
  }

  Future<List<PodcastEpisode>> _loadEpisodesForPodcast(
    String podcastId,
    Map<String, dynamic> firstPage,
  ) async {
    final episodes = <PodcastEpisode>[];
    final seenIds = <String>{};

    Future<void> addPage(Map<String, dynamic> page) async {
      final items = _asList(page['episodes']) ?? const <dynamic>[];
      for (final item in items) {
        if (item is! Map) continue;
        final episode = Map<String, dynamic>.from(item as Map);

        final audioUrl = _asString(episode['audio']);
        if (audioUrl == null || audioUrl.isEmpty) continue;

        final episodeId = _asString(episode['id']) ?? audioUrl;
        if (seenIds.contains(episodeId)) continue;
        seenIds.add(episodeId);

        episodes.add(
          PodcastEpisode(
            id: episodeId,
            showId: podcastId,
            title: _asString(episode['title']) ??
                _asString(episode['title_original']) ??
                'Untitled episode',
            description: _strip(
              _asString(episode['description']) ??
                  _asString(episode['description_original']) ??
                  '',
            ),
            audioUrl: audioUrl,
            artworkUrl: _asString(episode['image']) ??
                _asString(episode['thumbnail']) ??
                _asString(firstPage['image']) ??
                _asString(firstPage['thumbnail']),
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
    }

    await addPage(firstPage);

    var nextEpisodePubDate = _asInt(firstPage['next_episode_pub_date']);
    var safety = 0;

    while (nextEpisodePubDate != null && safety < 20) {
      safety += 1;

      final page = await _fetchJson(
        Uri.parse('$_baseUrl/podcasts/${Uri.encodeComponent(podcastId)}')
            .replace(queryParameters: {
          'next_episode_pub_date': nextEpisodePubDate.toString(),
          'sort': 'recent_first',
        }),
      );

      final beforeCount = episodes.length;
      await addPage(page);

      nextEpisodePubDate = _asInt(page['next_episode_pub_date']);

      if (episodes.length == beforeCount) {
        break;
      }
    }

    return episodes;
  }

  Future<PodcastShow> _loadFromRss(
    String url, {
    required PodcastSearchResult fallback,
  }) async {
    final xml = await _getString(url);
    final channel = _first(xml, 'channel') ?? xml;

    final title = _text(channel, 'title') ?? fallback.title;
    final description = _strip(
      _text(channel, 'description') ?? fallback.description,
    );
    final publisher = _text(channel, 'itunes:author') ??
        _text(channel, 'author') ??
        fallback.publisher;
    final artwork = _image(channel) ?? fallback.artworkUrl;

    final episodes = <PodcastEpisode>[];
    for (final item in _all(channel, 'item')) {
      final audioUrl = _episodeAudioUrl(item);
      if (audioUrl == null || audioUrl.isEmpty) continue;

      episodes.add(
        PodcastEpisode(
          id: audioUrl,
          showId: fallback.id,
          title: _text(item, 'title') ?? 'Untitled episode',
          description: _strip(
            _text(item, 'description') ??
                _text(item, 'itunes:summary') ??
                '',
          ),
          audioUrl: audioUrl,
          artworkUrl: _image(item) ?? artwork,
          publishDate: _parseRssDate(_text(item, 'pubDate')),
          duration: _parseDuration(_text(item, 'itunes:duration')),
        ),
      );
    }

    return PodcastShow(
      id: fallback.id,
      title: title,
      description: description,
      publisher: publisher,
      feedUrl: url,
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
        title;

    final description = _strip(
      _asString(item['description_original']) ??
          _asString(item['description']) ??
          _asString(item['description_highlighted']) ??
          '',
    );

    return PodcastSearchResult(
      id: id,
      title: title,
      publisher: publisher,
      feedUrl: _asString(item['rss']) ?? '',
      description: description,
      artworkUrl: _asString(item['image']) ?? _asString(item['thumbnail']),
    );
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final body = await _request(uri);
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON response from Listen Notes');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<String> _request(Uri uri) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'Listen Notes API key is missing. Pass --dart-define=LISTEN_NOTES_API_KEY=...',
      );
    }

    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('X-ListenAPI-Key', _apiKey);

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

  Future<String> _getString(String url) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'musicplayer/1.4.8');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/rss+xml, application/xml, text/xml, */*',
    );

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Podcast feed failed: HTTP ${response.statusCode} for $url\n$body',
      );
    }

    return body;
  }

  static bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
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

  static DateTime? _parseRssDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return HttpDate.parse(raw).toLocal();
    } on FormatException {
      return null;
    }
  }

  static Duration? _parseDurationSeconds(int? seconds) {
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  static Duration? _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final parts = raw.split(':').map((e) => int.tryParse(e.trim())).toList();
    if (parts.any((e) => e == null)) return null;

    if (parts.length == 3) {
      return Duration(
        hours: parts[0]!,
        minutes: parts[1]!,
        seconds: parts[2]!,
      );
    }

    if (parts.length == 2) {
      return Duration(
        minutes: parts[0]!,
        seconds: parts[1]!,
      );
    }

    if (parts.length == 1) {
      return Duration(seconds: parts[0]!);
    }

    return null;
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

  static Iterable<String> _all(String xml, String tag) sync* {
    final re = RegExp(
      '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    );
    for (final match in re.allMatches(xml)) {
      final inner = match.group(1);
      if (inner != null) yield inner;
    }
  }

  static String? _first(String xml, String tag) {
    final iterator = _all(xml, tag).iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }

  static String? _text(String xml, String tag) => _decode(_first(xml, tag) ?? '');

  static String? _image(String xml) {
    final itunes = RegExp(
      r"""<itunes:image\b[^>]*href=['"]([^'"]+)['"]""",
      caseSensitive: false,
    ).firstMatch(xml)?.group(1);
    if (itunes != null && itunes.isNotEmpty) return _decode(itunes);

    final image = _first(xml, 'image');
    if (image == null) return null;

    return _text(image, 'url');
  }

  static String? _episodeAudioUrl(String xml) {
    final enclosure = _extractAttr(
      xml,
      tagPattern: r'enclosure',
      attrName: 'url',
    );
    if (enclosure != null && enclosure.isNotEmpty) return _decode(enclosure);

    final mediaContent = _extractAttr(
      xml,
      tagPattern: r'media:content',
      attrName: 'url',
    );
    if (mediaContent != null && mediaContent.isNotEmpty) {
      return _decode(mediaContent);
    }

    final link = _text(xml, 'link');
    if (link != null && link.startsWith('http')) return link;

    return null;
  }

  static String? _extractAttr(
    String xml, {
    required String tagPattern,
    required String attrName,
  }) {
    final re = RegExp(
      '<$tagPattern\\b[^>]*\\b$attrName=[\'"]([^\'"]+)[\'"]',
      caseSensitive: false,
    );
    return re.firstMatch(xml)?.group(1);
  }
}
