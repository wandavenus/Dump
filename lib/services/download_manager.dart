import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'extensions/extension_service.dart';
import 'extensions/models/download_item.dart';
import 'extensions/models/online_track.dart';
import 'media_store_service.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();
  final List<DownloadItem> _items = [];
  bool _running = false;
  Future<File> get _state async => File(
    p.join(
      (await getApplicationDocumentsDirectory()).path,
      'download_queue.json',
    ),
  );
  List<DownloadItem> get items => List.unmodifiable(_items);
  Future<void> load() async {
    try {
      final f = await _state;
      if (f.existsSync()) {
        _items
          ..clear()
          ..addAll(
            (jsonDecode(await f.readAsString()) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map((e) => DownloadItem.fromJson(e)),
          );
        notifyListeners();
      }
    } on Object {
      // Ignore corrupt persisted queue state and start with an empty queue.
    }
  }

  Future<void> _persist() async {
    final f = await _state;
    await f.writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  void enqueue(OnlineTrack track) {
    _items.insert(
      0,
      DownloadItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        track: track,
        status: DownloadStatus.queued,
        progress: 0,
      ),
    );
    notifyListeners();
    unawaited(_persist());
    unawaited(_pump());
  }

  void cancel(String id) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i >= 0) {
      _items[i] = _items[i].copyWith(status: DownloadStatus.cancelled);
      notifyListeners();
      unawaited(_persist());
    }
  }

  void retry(String id) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i >= 0) {
      _items[i] = _items[i].copyWith(
        status: DownloadStatus.queued,
        progress: 0,
        error: null,
      );
      notifyListeners();
      unawaited(_persist());
      unawaited(_pump());
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final i = _items.indexWhere((e) => e.status == DownloadStatus.queued);
        if (i < 0) break;
        await _download(i);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _download(int index) async {
    var item = _items[index];
    try {
      _items[index] = item.copyWith(status: DownloadStatus.downloading);
      notifyListeners();
      final runtime = ExtensionService.instance.runtimeFor(
        item.track.extensionId,
      );
      if (runtime == null) throw Exception('Extension runtime not available');
      final dir = Directory(
        p.join(
          (await getExternalStorageDirectory() ??
                  await getApplicationDocumentsDirectory())
              .path,
          'Downloads',
        ),
      );
      await dir.create(recursive: true);
      final safe = '${item.track.artist} - ${item.track.title}'.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final out = File(p.join(dir.path, '$safe.flac'));
      final providerResult = await runtime.download(
        item.track,
        out.path,
        onProgress: (progress) {
          _items[index] = item.copyWith(progress: progress);
          notifyListeners();
        },
      );
      final url = providerResult.downloadUrl;
      if (providerResult.success &&
          providerResult.filePath != null &&
          File(providerResult.filePath!).existsSync()) {
        await MediaStoreService.scanFile(providerResult.filePath!);
        _items[index] = _items[index].copyWith(
          status: DownloadStatus.completed,
          progress: 1,
          filePath: providerResult.filePath,
        );
        MediaStoreService.rescanNotifier.value++;
        return;
      }
      if (url == null || url.isEmpty) {
        throw Exception(providerResult.error ?? 'No download URL');
      }
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final ext = p.extension(Uri.parse(url).path).isEmpty
          ? '.flac'
          : p.extension(Uri.parse(url).path);
      final tmp = File(p.join(dir.path, '$safe.part'));
      final downloaded = File(p.join(dir.path, '$safe$ext'));
      final sink = tmp.openWrite();
      var got = 0;
      final total = res.contentLength ?? 0;
      final sw = Stopwatch()..start();
      await for (final chunk in res.stream) {
        item = _items[index];
        if (item.status == DownloadStatus.cancelled) {
          await sink.close();
          client.close();
          return;
        }
        got += chunk.length;
        sink.add(chunk);
        _items[index] = item.copyWith(
          progress: total > 0 ? got / total : 0,
          speedBytesPerSecond:
              got / (sw.elapsedMilliseconds.clamp(1, 1 << 31) / 1000),
        );
        notifyListeners();
      }
      await sink.close();
      client.close();
      if (downloaded.existsSync()) await downloaded.delete();
      await tmp.rename(downloaded.path);
      await MediaStoreService.scanFile(downloaded.path);
      _items[index] = _items[index].copyWith(
        status: DownloadStatus.completed,
        progress: 1,
        filePath: downloaded.path,
      );
      MediaStoreService.rescanNotifier.value++;
    } on Object catch (e) {
      _items[index] = _items[index].copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
      );
    }
    notifyListeners();
    await _persist();
  }
}
