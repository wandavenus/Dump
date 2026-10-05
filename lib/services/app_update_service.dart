import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AppUpdateInfo {
  final String version;
  final String tagName;
  final String releaseName;
  final String changelog;
  final String apkUrl;
  final String apkName;

  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.changelog,
    required this.apkUrl,
    required this.apkName,
  });
}

class AppUpdateService {
  AppUpdateService._();

  static const _channel = MethodChannel('musicplayer/app_update');
  static const _latestReleaseUrl =
      'https://api.github.com/repos/wandavenus/Dump/releases/latest';

  static bool _startupCheckStarted = false;
  static const _autoCheckKey = 'app_update_auto_check';
  static bool autoCheckOnStartup = true;
  static bool _settingsLoaded = false;

  static Future<void> loadSettings() async {
    if (_settingsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    autoCheckOnStartup = prefs.getBool(_autoCheckKey) ?? true;
    _settingsLoaded = true;
  }

  static Future<void> setAutoCheckOnStartup(bool value) async {
    autoCheckOnStartup = value;
    _settingsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckKey, value);
  }

  static Future<void> checkOnStartup(
    BuildContext context,
    Widget Function(BuildContext, AppUpdateInfo) pageBuilder,
  ) async {
    await loadSettings();
    if (!autoCheckOnStartup || _startupCheckStarted) return;
    _startupCheckStarted = true;

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!context.mounted) return;

    try {
      final update = await checkForUpdate();
      if (update == null || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) => pageBuilder(pageContext, update),
        ),
      );
    } on Object catch (exception) {
      // Update checks are best-effort and must never affect app startup.
      debugPrint('Update check failed: $exception');
    }
  }

  static Future<AppUpdateInfo?> checkForUpdate() async {
    final versionInfo = await _channel.invokeMapMethod<String, dynamic>(
      'getVersionInfo',
    );
    final currentVersion = versionInfo?['versionName'] as String?;
    if (currentVersion == null || currentVersion.isEmpty) return null;

    final response = await http.get(
      Uri.parse(_latestReleaseUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2026-03-10',
        'User-Agent': 'MusicPlayer-Updater',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic> || json['draft'] == true) return null;

    final tagName = json['tag_name'] as String? ?? '';
    final version = _normalizeVersion(tagName);
    if (version == null || !_isNewer(version, currentVersion)) return null;

    final assets = json['assets'];
    if (assets is! List) return null;

    Map<String, dynamic>? apk;
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'];
        if (name is String && name.toLowerCase().endsWith('.apk')) {
          apk = asset;
          break;
        }
      }
    }

    if (apk == null) return null;

    final apkUrl = apk['browser_download_url'];
    final apkName = apk['name'];
    if (apkUrl is! String || apkName is! String) return null;

    return AppUpdateInfo(
      version: version,
      tagName: tagName,
      releaseName: json['name'] as String? ?? tagName,
      changelog: json['body'] as String? ?? '',
      apkUrl: apkUrl,
      apkName: apkName,
    );
  }

  static Future<String?> getCurrentVersion() async {
    final versionInfo = await _channel.invokeMapMethod<String, dynamic>(
      'getVersionInfo',
    );
    return versionInfo?['versionName'] as String?;
  }

  static Future<int?> startApkDownload(AppUpdateInfo update) {
    return _channel.invokeMethod<int>(
      'startApkDownload',
      {'url': update.apkUrl, 'fileName': update.apkName},
    );
  }

  static Future<Map<String, dynamic>?> getDownloadStatus(int id) {
    return _channel.invokeMapMethod<String, dynamic>(
      'getDownloadStatus',
      {'id': id},
    );
  }

  static Future<bool> canInstallPackages() async {
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() {
    return _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<bool> installDownloadedApk(int id) async {
    return await _channel.invokeMethod<bool>(
          'installDownloadedApk',
          {'id': id},
        ) ??
        false;
  }

  static String? _normalizeVersion(String raw) {
    final value = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[+\-].*)?$').firstMatch(value);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  static List<int>? _parseVersion(String raw) {
    final normalized = _normalizeVersion(raw);
    if (normalized == null) return null;
    return normalized.split('.').map(int.parse).toList();
  }

  static bool _isNewer(String remote, String current) {
    final r = _parseVersion(remote);
    final c = _parseVersion(current);
    if (r == null || c == null) return false;

    for (var i = 0; i < 3; i++) {
      if (r[i] != c[i]) return r[i] > c[i];
    }
    return false;
  }
}

