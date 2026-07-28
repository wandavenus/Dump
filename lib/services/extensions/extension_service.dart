import 'extension_installer.dart';
import 'extension_runtime.dart';
import 'models/extension_manifest.dart';
import 'models/online_track.dart';

class ExtensionService {
  ExtensionService._(); static final instance = ExtensionService._();
  final ExtensionInstaller installer = ExtensionInstaller();
  List<ExtensionManifest> _installed = const [];
  final Map<String, ExtensionRuntime> _runtimes = {};
  Future<List<ExtensionManifest>> loadInstalled() async {
    _installed = await installer.installed(); _runtimes..clear()..addEntries(_installed.map((m)=>MapEntry(m.id, HttpTemplateExtensionRuntime(m)))); return _installed;
  }
  List<ExtensionManifest> get installedExtensions => _installed;
  ExtensionRuntime? runtimeFor(String id)=>_runtimes[id];
  Future<List<OnlineTrack>> search(String query) async {
    if (_runtimes.isEmpty) await loadInstalled();
    final results = await Future.wait(_runtimes.values.map((r)=>r.search(query).catchError((Object _) => <OnlineTrack>[])));
    return results.expand((e)=>e).toList(growable:false);
  }
}
