import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/extension_manifest.dart';
import 'models/online_track.dart';

abstract class ExtensionRuntime {
  String get extensionId;
  Future<List<OnlineTrack>> search(String query);
  Future<String?> resolveDownloadUrl(OnlineTrack track);
}

class HttpTemplateExtensionRuntime implements ExtensionRuntime {
  HttpTemplateExtensionRuntime(this.manifest, {http.Client? client}) : _client = client;
  final ExtensionManifest manifest; final http.Client? _client;
  @override String get extensionId => manifest.id;
  @override Future<List<OnlineTrack>> search(String query) async {
    final template = manifest.searchUrl; if (template == null || template.isEmpty) return const [];
    final client = _client ?? http.Client();
    try {
      final url = template.replaceAll('{query}', Uri.encodeQueryComponent(query));
      final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final decoded = jsonDecode(res.body);
      final list = decoded is List ? decoded : (decoded['tracks'] as List? ?? decoded['results'] as List? ?? const []);
      return list.whereType<Map>().map((e)=>OnlineTrack.fromJson(e.cast<String,dynamic>(), extensionId)).where((t)=>t.id.isNotEmpty).toList(growable:false);
    } finally { if (_client == null) client.close(); }
  }
  @override Future<String?> resolveDownloadUrl(OnlineTrack track) async {
    final template = manifest.downloadUrlTemplate;
    if (template == null || template.isEmpty) return track.id.startsWith('http') ? track.id : null;
    return template.replaceAll('{id}', Uri.encodeQueryComponent(track.id));
  }
}
