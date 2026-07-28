import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/extension_entry.dart';

class ExtensionRegistryService {
  static const defaultRegistryUrl =
      'https://raw.githubusercontent.com/spotiflacapp/SpotiFLAC-Extension/main/registry.json';
  const ExtensionRegistryService({this._client});
  final http.Client? _client;
  Future<List<ExtensionEntry>> load(String url) async {
    final client = _client ?? http.Client();
    try {
      final res = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Registry HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded['extensions'] as List? ?? const []);
      return list
          .whereType<Map>()
          .map((e) => ExtensionEntry.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList(growable: false);
    } finally {
      if (_client == null) client.close();
    }
  }
}
