import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:path/path.dart' as p;

import 'extension_runtime_error.dart';
import 'models/extension_manifest.dart';
import 'models/online_track.dart';

abstract class ExtensionRuntime {
  String get extensionId;
  Future<void> initialize([Map<String, dynamic> settings = const {}]);
  Future<List<OnlineTrack>> search(String query, {int limit = 25});
  Future<OnlineTrack?> getTrack(String id);
  Future<String?> resolveDownloadUrl(OnlineTrack track);
  Future<ExtensionDownloadResult> download(
    OnlineTrack track,
    String outputPath, {
    String quality = 'best',
    void Function(double progress)? onProgress,
  });
  Future<void> cleanup();
}

class ExtensionDownloadResult {
  const ExtensionDownloadResult({
    required this.success,
    this.filePath,
    this.downloadUrl,
    this.error,
    this.errorType,
  });

  final bool success;
  final String? filePath;
  final String? downloadUrl;
  final String? error;
  final String? errorType;
}

class JsExtensionRuntime implements ExtensionRuntime {
  JsExtensionRuntime(this.manifest, this.sourceDir);

  final ExtensionManifest manifest;
  final Directory sourceDir;
  JavascriptRuntime? _js;
  bool _initialized = false;

  @override
  String get extensionId => manifest.id;

  @override
  Future<void> initialize([Map<String, dynamic> settings = const {}]) async {
    try {
      manifest.validate();
      final js = getJavascriptRuntime(xhr: true);
      _js = js;
      await _injectBridge(js);
      final entry = File(p.join(sourceDir.path, manifest.entrypoint));
      if (!entry.existsSync()) {
        throw ExtensionRuntimeException(
          extensionId,
          'load',
          'entrypoint not found',
        );
      }
      final result = js.evaluate(
        entry.readAsStringSync(),
        sourceUrl: entry.path,
      );
      if (result.isError) {
        throw ExtensionRuntimeException(
          extensionId,
          'execute',
          result.stringResult,
        );
      }
      final registered = js.evaluate('typeof extension !== "undefined"');
      if (registered.stringResult != 'true') {
        throw ExtensionRuntimeException(
          extensionId,
          'register',
          'extension did not call registerExtension()',
        );
      }
      await _callJson('initialize', [settings], allowMissing: true);
      _initialized = true;
    } catch (e) {
      if (e is ExtensionRuntimeException) rethrow;
      throw ExtensionRuntimeException(extensionId, 'initialize', e.toString());
    }
  }

  Future<void> _injectBridge(JavascriptRuntime js) async {
    final bootstrap = '''
      var extension;
      function registerExtension(value) { extension = value; }
      var console = { log: function(){}, warn: function(){}, error: function(){}, info: function(){} };
      var log = console;
      var storage = {
        get: function(k){ return __dartStorageGet(String(k)); },
        set: function(k,v){ return __dartStorageSet(String(k), String(v)); },
        remove: function(k){ return __dartStorageRemove(String(k)); }
      };
      var credentials = storage;
      var utils = {
        appVersion: function(){ return '4.7.0'; },
        appUserAgent: function(){ return 'SpotiFLAC-Mobile/4.7.0'; },
        randomUserAgent: function(){ return 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36'; },
        base64Encode: function(v){ return btoa(String(v)); },
        base64Decode: function(v){ return atob(String(v)); },
        md5: function(v){ return __dartHash('md5', String(v)); },
        sha256: function(v){ return __dartHash('sha256', String(v)); },
        hmacSHA1: function(k,v){ return __dartHmac('sha1', String(k), String(v)); },
        hmacSHA256: function(k,v){ return __dartHmac('sha256', String(k), String(v)); },
        hmacSHA256Base64: function(k,v){ return __dartHmac('sha256b64', String(k), String(v)); },
        parseJSON: function(v){ return JSON.parse(String(v)); },
        stringifyJSON: function(v){ return JSON.stringify(v); },
        sleep: function(){ return true; },
        isDownloadCancelled: function(){ return false; },
        isRequestCancelled: function(){ return false; },
        setDownloadStatus: function(){ return true; }
      };
      var http = {
        get: function(url, headers){ return __dartHttp('GET', String(url), '', JSON.stringify(headers || {})); },
        post: function(url, body, headers){ return __dartHttp('POST', String(url), String(body || ''), JSON.stringify(headers || {})); },
        put: function(url, body, headers){ return __dartHttp('PUT', String(url), String(body || ''), JSON.stringify(headers || {})); },
        patch: function(url, body, headers){ return __dartHttp('PATCH', String(url), String(body || ''), JSON.stringify(headers || {})); },
        delete: function(url, headers){ return __dartHttp('DELETE', String(url), '', JSON.stringify(headers || {})); },
        request: function(method, url, body, headers){ return __dartHttp(String(method || 'GET'), String(url), String(body || ''), JSON.stringify(headers || {})); },
        clearCookies: function(){ return true; }
      };
      var file = {
        download: function(url, outputPath, options){ return __dartFileDownload(String(url), String(outputPath), JSON.stringify(options || {})); },
        exists: function(path){ return __dartFileExists(String(path)); },
        read: function(path){ return __dartFileRead(String(path)); },
        write: function(path, value){ return __dartFileWrite(String(path), String(value)); }
      };
    ''';
    js.evaluate(bootstrap);
    js.evaluate(_dartCallbackSource());
  }

  String _dartCallbackSource() => '''
    function __dartStorageGet(k){ return null; }
    function __dartStorageSet(k,v){ return true; }
    function __dartStorageRemove(k){ return true; }
    function __dartHash(a,v){ return ''; }
    function __dartHmac(a,k,v){ return ''; }
    function __dartHttp(method,url,body,headers){ throw new Error('Synchronous native HTTP bridge unavailable in this runtime build'); }
    function __dartFileDownload(url,path,options){ return { success:false, error:'file bridge unavailable', download_url:url }; }
    function __dartFileExists(path){ return false; }
    function __dartFileRead(path){ return ''; }
    function __dartFileWrite(path,value){ return false; }
  ''';

  Future<dynamic> _callJson(
    String method,
    List<Object?> args, {
    bool allowMissing = false,
  }) async {
    if (!_initialized && method != 'initialize') {
      await initialize();
    }
    final js = _js;
    if (js == null) {
      throw ExtensionRuntimeException(
        extensionId,
        method,
        'runtime not loaded',
      );
    }
    final script =
        '''
      (function(){
        if (!extension || typeof extension['$method'] !== 'function') {
          return JSON.stringify({__missing:true});
        }
        try { return JSON.stringify({value: extension['$method'].apply(extension, ${jsonEncode(args)})}); }
        catch(e) { return JSON.stringify({__error: String(e && (e.stack || e.message) || e)}); }
      })()
    ''';
    final result = js.evaluate(script);
    if (result.isError) {
      throw ExtensionRuntimeException(extensionId, method, result.stringResult);
    }
    final decoded = jsonDecode(result.stringResult) as Map<String, dynamic>;
    if (decoded['__missing'] == true) {
      if (allowMissing) return null;
      throw ExtensionRuntimeException(
        extensionId,
        method,
        'method not implemented',
      );
    }
    if (decoded['__error'] != null) {
      throw ExtensionRuntimeException(
        extensionId,
        method,
        decoded['__error'].toString(),
      );
    }
    return decoded['value'];
  }

  @override
  Future<List<OnlineTrack>> search(String query, {int limit = 25}) async {
    final value = await _callJson('searchTracks', [query, limit]);
    final tracks = value is Map<String, dynamic> ? value['tracks'] : value;
    return (tracks as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => OnlineTrack.fromJson(e, extensionId))
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<OnlineTrack?> getTrack(String id) async {
    final value = await _callJson('getTrack', [id], allowMissing: true);
    if (value is! Map<String, dynamic>) {
      return null;
    }
    return OnlineTrack.fromJson(value.cast<String, dynamic>(), extensionId);
  }

  @override
  Future<String?> resolveDownloadUrl(OnlineTrack track) async {
    final value = await _callJson('download', [
      track.id,
      track.quality ?? 'best',
      '',
      null,
    ], allowMissing: true);
    if (value is Map<String, dynamic>) {
      return (value['download_url'] ?? value['downloadUrl'] ?? value['url'])
          ?.toString();
    }
    if (manifest.downloadUrlTemplate != null) {
      return manifest.downloadUrlTemplate!.replaceAll(
        '{id}',
        Uri.encodeQueryComponent(track.id),
      );
    }
    return null;
  }

  @override
  Future<ExtensionDownloadResult> download(
    OnlineTrack track,
    String outputPath, {
    String quality = 'best',
    void Function(double progress)? onProgress,
  }) async {
    final value = await _callJson('download', [
      track.id,
      quality,
      outputPath,
      null,
    ]);
    if (value is Map<String, dynamic>) {
      return ExtensionDownloadResult(
        success: value['success'] == true,
        filePath: (value['file_path'] ?? value['filePath'] ?? outputPath)
            .toString(),
        downloadUrl:
            (value['download_url'] ?? value['downloadUrl'] ?? value['url'])
                ?.toString(),
        error: value['error']?.toString(),
        errorType: value['error_type']?.toString(),
      );
    }
    return const ExtensionDownloadResult(
      success: false,
      error: 'invalid download result',
    );
  }

  @override
  Future<void> cleanup() async {
    await _callJson('cleanup', const [], allowMissing: true);
    _js?.dispose();
  }
}
