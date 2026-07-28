import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'extension_installer.dart';
import 'extension_runtime.dart';
import 'models/extension_manifest.dart';
import 'models/online_track.dart';

class ExtensionService {
  ExtensionService._();
  static final instance = ExtensionService._();

  final ExtensionInstaller installer = ExtensionInstaller();
  List<ExtensionManifest> _installed = const [];
  final Map<String, ExtensionRuntime> _runtimes = {};
  final Map<String, Object> _errors = {};

  List<ExtensionManifest> get installedExtensions => _installed;
  Map<String, Object> get runtimeErrors => Map.unmodifiable(_errors);

  ExtensionRuntime? runtimeFor(String id) => _runtimes[id];

  Future<List<ExtensionManifest>> loadInstalled() async {
    _installed = await installer.installed();
    _runtimes.clear();
    _errors.clear();
    final root = await installer.root;
    for (final manifest in _installed) {
      try {
        final runtime = JsExtensionRuntime(
          manifest,
          Directory(p.join(root.path, manifest.id)),
        );
        await runtime.initialize();
        _runtimes[manifest.id] = runtime;
      } on Object catch (error) {
        _errors[manifest.id] = error;
      }
    }
    return _installed;
  }

  Future<List<OnlineTrack>> search(String query, {int limit = 25}) async {
    if (_runtimes.isEmpty && _errors.isEmpty) await loadInstalled();
    final results = await Future.wait(
      _runtimes.values.map(
        (runtime) => runtime.search(query, limit: limit).catchError((Object e) {
          _errors[runtime.extensionId] = e;
          return <OnlineTrack>[];
        }),
      ),
    );
    return results.expand((e) => e).toList(growable: false);
  }

  Future<void> cleanup() async {
    await Future.wait(_runtimes.values.map((runtime) => runtime.cleanup()));
    _runtimes.clear();
  }
}
