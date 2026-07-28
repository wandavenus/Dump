import 'dart:async';

import 'package:flutter/services.dart';

import '../models/extension_manifest.dart';

class ExtensionJsRuntimeV2 {
  static const MethodChannel _channel = MethodChannel('musicplayer/extension_js_engine');

  final String extensionId;
  final Duration timeout;

  const ExtensionJsRuntimeV2({required this.extensionId, this.timeout = const Duration(seconds: 30)});

  Future<void> initialize({required String jsCode, required ExtensionManifest manifest}) {
    return _invoke<void>('initialize', <String, Object?>{
      'extensionId': extensionId,
      'jsCode': jsCode,
      'manifest': manifest.toJson(),
      'timeoutMs': timeout.inMilliseconds,
    });
  }

  Future<List<Map<String, dynamic>>> callSearch(String query, Map<String, dynamic> settings) async {
    final result = await _invoke<Object?>('search', <String, Object?>{
      'extensionId': extensionId,
      'query': query,
      'settings': settings,
    });
    return _decodeMapList(result);
  }

  Future<Map<String, dynamic>?> callGetDownloadUrl(
    Map<String, dynamic> track,
    String quality,
    Map<String, dynamic> settings,
  ) async {
    final result = await _invoke<Object?>('getDownloadUrl', <String, Object?>{
      'extensionId': extensionId,
      'track': track,
      'quality': quality,
      'settings': settings,
    });
    return _decodeNullableMap(result);
  }

  Future<List<Map<String, dynamic>>> callGetAlbumTracks(String albumId, Map<String, dynamic> settings) async {
    final result = await _invoke<Object?>('getAlbumTracks', <String, Object?>{
      'extensionId': extensionId,
      'albumId': albumId,
      'settings': settings,
    });
    return _decodeMapList(result);
  }

  Future<void> dispose() {
    return _invoke<void>('dispose', <String, Object?>{'extensionId': extensionId});
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) {
    return _channel.invokeMethod<T>(method, arguments).timeout(timeout);
  }
}

List<Map<String, dynamic>> _decodeMapList(Object? value) {
  if (value is! List<Object?>) return const <Map<String, dynamic>>[];
  return value.map(_decodeRequiredMap).toList(growable: false);
}

Map<String, dynamic>? _decodeNullableMap(Object? value) {
  if (value == null) return null;
  return _decodeRequiredMap(value);
}

Map<String, dynamic> _decodeRequiredMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<Object?, Object?>) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  throw FormatException('Expected a map from extension runtime, got ${value.runtimeType}.');
}
