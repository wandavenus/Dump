import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import '../services/download_manager.dart';
import '../services/extensions/models/download_item.dart';
import '../utils/zoom_fade_route.dart';
import 'extension_manager_page.dart';

class DownloadQueuePage extends StatefulWidget {
  const DownloadQueuePage({super.key});
  @override
  State<DownloadQueuePage> createState() => _DownloadQueuePageState();
}

class _DownloadQueuePageState extends State<DownloadQueuePage> {
  final DownloadManager _m = DownloadManager.instance;
  @override
  void initState() {
    super.initState();
    unawaited(_m.load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Download Queue'),
      actions: [
        IconButton(
          icon: const Icon(Icons.link),
          onPressed: () => Navigator.of(
            context,
          ).push(ZoomFadeRoute<void>(page: const ExtensionManagerPage())),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: _m,
      builder: (context, _) {
        final items = _m.items;
        if (items.isEmpty) return const Center(child: Text('No downloads yet'));
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            return ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(it.track.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${it.track.artist} • ${it.status.name}${it.error == null ? '' : ' • ${it.error}'}',
                  ),
                  if (it.status == DownloadStatus.downloading) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: it.progress <= 0 ? null : it.progress,
                    ),
                    Text(
                      '${(it.progress * 100).toStringAsFixed(0)}% • ${_speed(it.speedBytesPerSecond)}',
                    ),
                  ],
                  if (it.filePath != null)
                    Text(
                      it.filePath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: switch (it.status) {
                DownloadStatus.downloading ||
                DownloadStatus.queued => IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _m.cancel(it.id),
                ),
                DownloadStatus.failed => IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _m.retry(it.id),
                ),
                _ => null,
              },
            );
          },
        );
      },
    ),
  );
  String _speed(double b) => b > 1024 * 1024
      ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB/s'
      : '${(b / 1024).toStringAsFixed(0)} KB/s';
}
