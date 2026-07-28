import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_url_result.dart';
import '../models/online_track.dart';

abstract class ExtensionDownloadResolver {
  Future<DownloadUrlResult?> getDownloadUrl(
    OnlineTrack track,
    String quality,
    String extensionId,
  );
}

class ExtensionPriorityService {
  static const _metadataPriorityKey = 'hybrid_metadata_provider_priority_v1';
  static const _downloadPriorityKey = 'hybrid_download_provider_priority_v1';

  final SharedPreferences _preferences;
  final ExtensionDownloadResolver? _downloadResolver;

  ExtensionPriorityService(this._preferences, {ExtensionDownloadResolver? downloadResolver})
    : _downloadResolver = downloadResolver;

  List<String> get metadataProviderPriority => _readPriority(_metadataPriorityKey);

  List<String> get downloadProviderPriority => _readPriority(_downloadPriorityKey);

  Future<void> setMetadataProviderPriority(List<String> order) {
    return _writePriority(_metadataPriorityKey, order);
  }

  Future<void> setDownloadProviderPriority(List<String> order) {
    return _writePriority(_downloadPriorityKey, order);
  }

  Future<DownloadUrlResult?> getDownloadUrlWithFallback(
    OnlineTrack track,
    String quality,
  ) async {
    final resolver = _downloadResolver;
    if (resolver == null) {
      throw StateError('ExtensionDownloadResolver is required for fallback resolution.');
    }

    final failures = <Object>[];
    for (final extensionId in downloadProviderPriority) {
      try {
        final result = await resolver.getDownloadUrl(track, quality, extensionId);
        if (result != null) return result;
      } on Object catch (error) {
        failures.add(error);
      }
    }

    if (failures.isNotEmpty) {
      throw StateError('All download providers failed: ${failures.length} failure(s).');
    }
    return null;
  }

  List<String> _readPriority(String key) {
    return _preferences.getStringList(key) ?? const <String>[];
  }

  Future<void> _writePriority(String key, List<String> order) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final id in order) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      normalized.add(trimmed);
    }
    return _preferences.setStringList(key, normalized);
  }
}
