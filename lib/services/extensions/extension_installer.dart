import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models/extension_entry.dart';
import 'models/extension_manifest.dart';

class ExtensionInstaller {
  Future<Directory> get root async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'extensions'),
  )..createSync(recursive: true);
  Future<List<ExtensionManifest>> installed() async {
    final dir = await root;
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) {
          final f = File(p.join(d.path, 'manifest.json'));
          if (!f.existsSync()) return null;
          try {
            return ExtensionManifest.fromJson(
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<ExtensionManifest>()
        .toList(growable: false);
  }

  Future<ExtensionManifest> install(ExtensionEntry entry) async {
    if (entry.packageUrl.isEmpty) {
      throw Exception('Extension package URL is empty');
    }
    final res = await http
        .get(Uri.parse(entry.packageUrl))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Package HTTP ${res.statusCode}');
    }
    final target = Directory(p.join((await root).path, entry.id));
    final tmp = Directory('${target.path}.tmp');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    if (entry.packageUrl.toLowerCase().endsWith('.zip')) {
      for (final file in ZipDecoder().decodeBytes(res.bodyBytes).files) {
        final outPath = p.normalize(p.join(tmp.path, file.name));
        if (!p.isWithin(tmp.path, outPath) && outPath != tmp.path) continue;
        if (file.isFile) {
          File(outPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(file.content as List<int>);
        }
      }
    } else {
      File(p.join(tmp.path, 'index.js')).writeAsBytesSync(res.bodyBytes);
      File(
        p.join(tmp.path, 'manifest.json'),
      ).writeAsStringSync(jsonEncode(entryToManifest(entry).toJson()));
    }
    final manifestFile = File(p.join(tmp.path, 'manifest.json'));
    if (!manifestFile.existsSync()) throw Exception('manifest.json not found');
    final manifest = ExtensionManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>,
    );
    if (!manifest.isValid ||
        !File(p.join(tmp.path, manifest.entrypoint)).existsSync()) {
      throw Exception('Invalid extension manifest');
    }
    if (target.existsSync()) target.deleteSync(recursive: true);
    tmp.renameSync(target.path);
    return manifest;
  }

  ExtensionManifest entryToManifest(ExtensionEntry e) => ExtensionManifest(
    id: e.id,
    name: e.name,
    version: e.version,
    author: e.author,
    description: e.description,
    type: e.type,
    entrypoint: 'index.js',
  );
  Future<void> uninstall(String id) async {
    final d = Directory(p.join((await root).path, id));
    if (d.existsSync()) await d.delete(recursive: true);
  }
}
