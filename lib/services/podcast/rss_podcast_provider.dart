import 'dart:convert';
import 'dart:io';

import '../../models/podcast_episode.dart';
import '../../models/podcast_search_result.dart';
import '../../models/podcast_show.dart';
import 'podcast_provider.dart';

class RssPodcastProvider implements PodcastProvider {
  RssPodcastProvider({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const List<PodcastSearchResult> _catalog = [
    PodcastSearchResult(
      id: 'podkesmas',
      title: 'PODKESMAS',
      publisher: 'Podkesmas Asia Network',
      feedUrl: 'https://anchor.fm/s/1037c8cc/podcast/rss',
      description: 'Obrolan komedi dan kehidupan sehari-hari Indonesia.',
    ),
    PodcastSearchResult(
      id: 'makna-talks',
      title: 'Makna Talks',
      publisher: 'Makna Creative',
      feedUrl: 'https://anchor.fm/s/11fbc498/podcast/rss',
      description: 'Percakapan inspiratif dengan kreator dan pelaku industri.',
    ),
    PodcastSearchResult(
      id: 'endoftheday',
      title: 'Endgame with Gita Wirjawan',
      publisher: 'Gita Wirjawan',
      feedUrl: 'https://anchor.fm/s/8f7b5a4/podcast/rss',
      description: 'Dialog panjang tentang pengetahuan, bisnis, dan masyarakat.',
    ),
  ];

  @override
  Future<List<PodcastSearchResult>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _catalog;
    final direct = Uri.tryParse(query);
    if (direct != null && direct.hasScheme) {
      final result = PodcastSearchResult(
        id: direct.toString(),
        title: direct.host,
        publisher: direct.host,
        feedUrl: direct.toString(),
        description: 'RSS podcast feed',
      );
      return [result];
    }
    return _catalog.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.publisher.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<PodcastShow> loadShow(PodcastSearchResult result) async {
    final xml = await _getString(result.feedUrl);
    final channel = _first(xml, 'channel') ?? xml;
    final title = _text(channel, 'title') ?? result.title;
    final description = _strip(_text(channel, 'description') ?? result.description);
    final publisher = _text(channel, 'itunes:author') ?? _text(channel, 'author') ?? result.publisher;
    final artwork = _image(channel) ?? result.artworkUrl;
    final episodes = <PodcastEpisode>[];
    for (final item in _all(channel, 'item')) {
      final audioUrl = _enclosure(item);
      if (audioUrl == null || audioUrl.isEmpty) continue;
      final epTitle = _text(item, 'title') ?? 'Untitled episode';
      episodes.add(PodcastEpisode(
        id: audioUrl,
        showId: result.id,
        title: epTitle,
        description: _strip(_text(item, 'description') ?? _text(item, 'itunes:summary') ?? ''),
        audioUrl: audioUrl,
        artworkUrl: _image(item) ?? artwork,
        publishDate: _parseDate(_text(item, 'pubDate')),
        duration: _parseDuration(_text(item, 'itunes:duration')),
      ));
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

  Future<String> _getString(String url) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'musicplayer/1.4.8');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Podcast feed failed: HTTP ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  }

  static Iterable<String> _all(String xml, String tag) sync* {
    final re = RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false);
    for (final m in re.allMatches(xml)) {
      yield m.group(1)!;
    }
  }

  static String? _first(String xml, String tag) => _all(xml, tag).firstOrNull;
  static String? _text(String xml, String tag) => _decode(_first(xml, tag));
  static String? _image(String xml) => RegExp("""<itunes:image[^>]+href=['"]([^'"]+)""", caseSensitive: false).firstMatch(xml)?.group(1) ?? _text(_first(xml, 'image') ?? '', 'url');
  static String? _enclosure(String xml) => RegExp("""<enclosure[^>]+url=['"]([^'"]+)""", caseSensitive: false).firstMatch(xml)?.group(1);
  static String? _decode(String? s) => s?.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').replaceAll('&amp;', '&').replaceAll('&quot;', '"').trim();
  static String _strip(String s) => _decode(s)?.replaceAll(RegExp('<[^>]+>'), '').trim() ?? '';
  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return HttpDate.parse(raw).toLocal();
    } on FormatException {
      return null;
    }
  }

  static Duration? _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.any((e) => e == null)) return null;
    if (parts.length == 3) {
      return Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
    }
    if (parts.length == 2) {
      return Duration(minutes: parts[0]!, seconds: parts[1]!);
    }
    return Duration(seconds: parts[0]!);
  }
}
