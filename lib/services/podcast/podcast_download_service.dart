import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/podcast_episode.dart';

class PodcastDownloadTask {
  final PodcastEpisode episode;
  final double progress;
  final String? localPath;
  final Object? error;
  final bool isRunning;

  const PodcastDownloadTask({
    required this.episode,
    this.progress = 0,
    this.localPath,
    this.error,
    this.isRunning = false,
  });
}

class PodcastDownloadService {
  PodcastDownloadService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static final ValueNotifier<Map<String, PodcastDownloadTask>> tasks = ValueNotifier({});
  static final Map<String, HttpClientRequest> _requests = {};

  static Future<String?> localPathFor(PodcastEpisode episode) async {
    final file = File(await _targetPath(episode));
    return file.existsSync() ? file.path : null;
  }

  static Future<void> download(PodcastEpisode episode) async {
    final id = episode.id;
    tasks.value = {...tasks.value, id: PodcastDownloadTask(episode: episode, isRunning: true)};
    try {
      final file = File(await _targetPath(episode));
      await file.parent.create(recursive: true);
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(episode.audioUrl));
      _requests[id] = request;
      final response = await request.close();
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        final progress = total > 0 ? received / total : 0.0;
        tasks.value = {...tasks.value, id: PodcastDownloadTask(episode: episode, progress: progress, isRunning: true)};
      }
      await sink.close();
      _requests.remove(id);
      await scanFile(file.path);
      tasks.value = {...tasks.value, id: PodcastDownloadTask(episode: episode, progress: 1, localPath: file.path)};
    } on Object catch (e) {
      _requests.remove(id);
      tasks.value = {...tasks.value, id: PodcastDownloadTask(episode: episode, error: e)};
    }
  }

  static void cancel(PodcastEpisode episode) {
    _requests.remove(episode.id)?.abort();
    final next = Map<String, PodcastDownloadTask>.from(tasks.value)..remove(episode.id);
    tasks.value = next;
  }

  static Future<void> retry(PodcastEpisode episode) => download(episode);

  static Future<void> scanFile(String path) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    }
  }

  static Future<String> _targetPath(PodcastEpisode episode) async {
    final base = Platform.isAndroid
        ? Directory('/storage/emulated/0/Music/Podcasts')
        : await getApplicationDocumentsDirectory();
    final name = '${_safe(episode.title)}${_extension(episode.audioUrl)}';
    return p.join(base.path, name);
  }

  static String _safe(String value) => value.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]+'), '_').trim().take(80);
  static String _extension(String url) {
    final ext = p.extension(Uri.parse(url).path);
    return ext.isEmpty ? '.mp3' : ext;
  }
}

extension on String {
  String take(int max) => length <= max ? this : substring(0, max);
}
