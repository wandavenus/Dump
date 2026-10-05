import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/services/app_update_service.dart';
import 'package:musicplayer/theme/app_colors.dart';

class AppUpdaterPage extends StatefulWidget {
  final VoidCallback? onOpenChangelog;
  final AppUpdateInfo? initialUpdate;

  const AppUpdaterPage({
    super.key,
    this.onOpenChangelog,
    this.initialUpdate,
  });

  @override
  State<AppUpdaterPage> createState() => _AppUpdaterPageState();
}

class _AppUpdaterPageState extends State<AppUpdaterPage> {
  AppUpdateInfo? _update;
  String? _currentVersion;
  String? _error;
  bool _checking = false;
  bool _downloading = false;
  int? _downloadId;
  int _downloaded = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _update = widget.initialUpdate;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final version = await AppUpdateService.getCurrentVersion();
      if (mounted) setState(() => _currentVersion = version);
    } on Object {}

    if (_update == null) await _check();
  }

  Future<void> _check() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final update = await AppUpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _checking = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Gagal memeriksa pembaruan.';
      });
    }
  }

  Future<void> _startDownload() async {
    final update = _update;
    if (update == null || _downloading) return;

    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      final id = await AppUpdateService.startApkDownload(update);
      if (id == null) throw StateError('Download tidak dapat dimulai.');
      _downloadId = id;
      await _pollDownload();
    } on Object {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Gagal mengunduh pembaruan.';
      });
    }
  }

  Future<void> _pollDownload() async {
    final id = _downloadId;
    if (id == null) return;

    while (mounted) {
      final status = await AppUpdateService.getDownloadStatus(id);
      if (status == null) throw StateError('Status download tidak tersedia.');

      final state = status['status'] as String? ?? 'unknown';
      final downloaded = (status['downloaded'] as num?)?.toInt() ?? 0;
      final total = (status['total'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      setState(() {
        _downloaded = downloaded;
        _total = total;
      });

      if (state == 'successful') {
        await _install();
        return;
      }
      if (state == 'failed') throw StateError('Download gagal.');

      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  Future<void> _install() async {
    final id = _downloadId;
    if (id == null) return;

    if (!await AppUpdateService.canInstallPackages()) {
      await AppUpdateService.openInstallPermissionSettings();
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Izinkan instalasi dari aplikasi ini, lalu tekan Perbarui lagi.';
      });
      return;
    }

    final installed = await AppUpdateService.installDownloadedApk(id);
    if (!installed && mounted) {
      setState(() {
        _downloading = false;
        _error = 'Installer tidak dapat dibuka.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final progress = _total > 0
        ? (_downloaded / _total).clamp(0.0, 1.0)
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(CupertinoIcons.arrow_left),
          color: const Color(0xFFF92D48),
        ),
        title: const Text('Pembaruan'),
        actions: [
          if (widget.onOpenChangelog != null)
            PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.ellipsis),
              color: c.surface,
              onSelected: (value) {
                if (value == 'changelog') widget.onOpenChangelog!();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'changelog',
                  child: Text('Catatan Pembaruan'),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pembaruan Aplikasi',
              style: TextStyle(
                color: c.primaryLabel,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentVersion == null
                  ? 'Periksa versi terbaru dari GitHub.'
                  : 'Versi saat ini v$_currentVersion',
              style: TextStyle(
                color: c.secondaryLabel,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.separator.withValues(alpha: 0.45)),
              ),
              child: _checking
                  ? const _CheckingState()
                  : _update != null
                      ? _UpdateAvailable(
                          update: _update!,
                          downloading: _downloading,
                          progress: progress,
                          downloaded: _downloaded,
                          total: _total,
                          onUpdate: _startDownload,
                        )
                      : _LatestState(
                          currentVersion: _currentVersion,
                          onCheck: _check,
                        ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: _checking || _downloading ? null : _check,
                icon: const Icon(CupertinoIcons.refresh, size: 17),
                label: const Text('Periksa Lagi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckingState extends StatelessWidget {
  const _CheckingState();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(height: 4),
      SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      SizedBox(height: 18),
      Text('Memeriksa pembaruan...'),
    ],
  );
}

class _LatestState extends StatelessWidget {
  final String? currentVersion;
  final VoidCallback onCheck;

  const _LatestState({required this.currentVersion, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        const Icon(
          CupertinoIcons.checkmark_circle_fill,
          color: Color(0xFFF92D48),
          size: 50,
        ),
        const SizedBox(height: 16),
        Text(
          'Kamu sudah menggunakan versi terbaru',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.primaryLabel, fontSize: 19, fontWeight: FontWeight.w600),
        ),
        if (currentVersion != null) ...[
          const SizedBox(height: 6),
          Text('v$currentVersion', style: TextStyle(color: c.secondaryLabel, fontSize: 14)),
        ],
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onCheck, child: const Text('Periksa Lagi')),
      ],
    );
  }
}

class _UpdateAvailable extends StatelessWidget {
  final AppUpdateInfo update;
  final bool downloading;
  final double? progress;
  final int downloaded;
  final int total;
  final VoidCallback onUpdate;

  const _UpdateAvailable({
    required this.update,
    required this.downloading,
    required this.progress,
    required this.downloaded,
    required this.total,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFF92D48).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.arrow_down_circle_fill,
                color: Color(0xFFF92D48),
                size: 29,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pembaruan tersedia',
                    style: TextStyle(color: c.primaryLabel, fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text('v${update.version}', style: TextStyle(color: c.secondaryLabel, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          update.releaseName,
          style: TextStyle(color: c.primaryLabel, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Versi terbaru tersedia melalui GitHub Release.',
          style: TextStyle(color: c.secondaryLabel, fontSize: 14, height: 1.35),
        ),
        const SizedBox(height: 20),
        if (downloading) ...[
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            total > 0
                ? '${downloaded ~/ 1024 ~/ 1024} / ${total ~/ 1024 ~/ 1024} MB'
                : 'Mengunduh...',
            style: TextStyle(color: c.secondaryLabel, fontSize: 13),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onUpdate,
              icon: const Icon(CupertinoIcons.arrow_down_to_line),
              label: const Text('Perbarui Sekarang'),
            ),
          ),
      ],
    );
  }
}