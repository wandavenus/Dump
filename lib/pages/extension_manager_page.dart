import 'dart:async' show unawaited;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/extensions/extension_installer.dart';
import '../services/extensions/extension_registry_service.dart';
import '../services/extensions/extension_service.dart';
import '../services/extensions/models/extension_entry.dart';

class ExtensionManagerPage extends StatefulWidget {
  const ExtensionManagerPage({super.key});
  @override
  State<ExtensionManagerPage> createState() => _ExtensionManagerPageState();
}

class _ExtensionManagerPageState extends State<ExtensionManagerPage> {
  final _url = TextEditingController(
    text: ExtensionRegistryService.defaultRegistryUrl,
  );
  final _registry = const ExtensionRegistryService();
  final _installer = ExtensionInstaller();
  List<ExtensionEntry> _entries = [];
  Set<String> _installed = {};
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(_refreshInstalled());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _refreshInstalled() async {
    final installed = await ExtensionService.instance.loadInstalled();
    if (mounted) {
      setState(() => _installed = installed.map((e) => e.id).toSet());
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await _registry.load(_url.text.trim());
      if (mounted) setState(() => _entries = e);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load registry: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(ExtensionEntry e) async {
    try {
      await _installer.install(e);
      await _refreshInstalled();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${e.name} installed')));
      }
    } on Object catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Install failed: $err')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Extension Manager')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Registry URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _load,
          child: Text(_loading ? 'Loading...' : 'Load Extensions'),
        ),
        const Divider(height: 32),
        Text('Extension List', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._entries.map(
          (e) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: e.iconUrl == null
                        ? const Icon(Icons.extension, size: 48)
                        : CachedNetworkImage(
                            imageUrl: e.iconUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                const Icon(Icons.extension, size: 48),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('by ${e.author} • v${e.version} • ${e.type}'),
                        const SizedBox(height: 6),
                        Text(e.description),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _installed.contains(e.id)
                        ? null
                        : () => unawaited(_install(e)),
                    child: Text(
                      _installed.contains(e.id) ? 'Installed' : 'Install',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
