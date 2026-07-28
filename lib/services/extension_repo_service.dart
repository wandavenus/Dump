import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/extension_manifest.dart';

class ExtensionRepoService {
  static const _repoUrlsKey = 'hybrid_extension_repo_urls_v1';

  final SharedPreferences _preferences;
  final http.Client _client;

  ExtensionRepoService(this._preferences, {http.Client? client}) : _client = client ?? http.Client();

  List<String> get savedRepoUrls => _preferences.getStringList(_repoUrlsKey) ?? const <String>[];

  Future<void> addRepoUrl(String url) async {
    final normalized = _normalizeRepoUrl(url);
    final urls = [...savedRepoUrls];
    if (!urls.contains(normalized)) urls.add(normalized);
    await _preferences.setStringList(_repoUrlsKey, urls);
  }

  Future<void> removeRepoUrl(String url) async {
    final normalized = _normalizeRepoUrl(url);
    final urls = savedRepoUrls.where((savedUrl) => savedUrl != normalized).toList(growable: false);
    await _preferences.setStringList(_repoUrlsKey, urls);
  }

  Future<List<ExtensionRepoEntry>> fetchRepoEntries(String repoUrl) async {
    final uri = Uri.parse(_normalizeRepoUrl(repoUrl));
    if (uri.scheme != 'https') {
      throw ArgumentError.value(repoUrl, 'repoUrl', 'Extension repositories must use HTTPS.');
    }

    final response = await _client.get(uri, headers: const {'accept': 'application/json'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ExtensionRepoException('Repository request failed with HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    final entriesJson = switch (decoded) {
      {'extensions': final List<Object?> entries} => entries,
      final List<Object?> entries => entries,
      _ => throw const FormatException('Registry must be a JSON list or contain an extensions list.'),
    };

    return entriesJson
        .map(_nullableObjectMap)
        .nonNulls
        .map((json) => ExtensionRepoEntry.fromJson(json, registryUrl: uri.toString()))
        .toList(growable: false);
  }

  Future<Map<String, String>> checkUpdates(Iterable<ExtensionManifest> installedExtensions) async {
    final installedById = {for (final extension in installedExtensions) extension.id: extension.version};
    final updates = <String, String>{};

    for (final repoUrl in savedRepoUrls) {
      final entries = await fetchRepoEntries(repoUrl);
      for (final entry in entries) {
        final installedVersion = installedById[entry.id];
        if (installedVersion == null) continue;
        if (_compareSemver(entry.version, installedVersion) > 0) {
          updates[entry.id] = entry.version;
        }
      }
    }

    return updates;
  }

  Future<Uri> resolveDownloadUri(ExtensionRepoEntry entry) async {
    final uri = Uri.parse(entry.downloadUrl);
    if (uri.scheme != 'https') {
      throw ArgumentError.value(entry.downloadUrl, 'downloadUrl', 'Extension downloads must use HTTPS.');
    }
    return uri;
  }

  static String _normalizeRepoUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(url, 'url', 'Repository URL is required.');
    return trimmed;
  }

  static int _compareSemver(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    for (var index = 0; index < 3; index += 1) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final core = version.split('-').first;
    final parts = core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    return [for (var i = 0; i < 3; i += 1) i < parts.length ? parts[i] : 0];
  }
}

class ExtensionRepoEntry {
  final String id;
  final String displayName;
  final String version;
  final String description;
  final String? author;
  final String downloadUrl;
  final String? iconUrl;
  final List<String> type;
  final String registryUrl;

  const ExtensionRepoEntry({
    required this.id,
    required this.displayName,
    required this.version,
    required this.description,
    this.author,
    required this.downloadUrl,
    this.iconUrl,
    required this.type,
    required this.registryUrl,
  });

  factory ExtensionRepoEntry.fromJson(Map<String, dynamic> json, {required String registryUrl}) {
    final id = json['id'] as String? ?? json['name'] as String? ?? '';
    return ExtensionRepoEntry(
      id: id,
      displayName: json['displayName'] as String? ?? json['name'] as String? ?? id,
      version: json['version'] as String? ?? '0.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String?,
      downloadUrl: json['downloadUrl'] as String? ?? json['url'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
      type: _stringList(json['type']),
      registryUrl: registryUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'version': version,
    'description': description,
    if (author != null) 'author': author,
    'downloadUrl': downloadUrl,
    if (iconUrl != null) 'iconUrl': iconUrl,
    'type': type,
    'registryUrl': registryUrl,
  };
}

class ExtensionRepoException implements Exception {
  final String message;

  const ExtensionRepoException(this.message);

  @override
  String toString() => 'ExtensionRepoException: $message';
}

List<String> _stringList(Object? value) {
  if (value is String) return [value];
  if (value is List<Object?>) return value.whereType<String>().toList(growable: false);
  return const <String>[];
}

Map<String, dynamic>? _nullableObjectMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}
