import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_audio_runtime/native_audio_runtime.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<_RuntimeSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  Future<_RuntimeSnapshot> _loadSnapshot() async {
    final runtime = NativeAudioRuntime.instance;
    await runtime.initialize();
    return _RuntimeSnapshot(
      isAvailable: runtime.isAvailable,
      version: runtime.version,
      capabilities: runtime.capabilities,
    );
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 20);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('native_audio_runtime')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<_RuntimeSnapshot>(
              future: _snapshot,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Text(
                    'Initializing native runtime…',
                    style: textStyle,
                  );
                }
                final data = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Runtime available: ${data.isAvailable}',
                      style: textStyle,
                    ),
                    spacerSmall,
                    Text('Version: ${data.version}', style: textStyle),
                    spacerSmall,
                    const Text('Capabilities (Phase 3 — all placeholders):',
                        style: textStyle),
                    for (final c in data.capabilities)
                      Text('  ${c.key}: supported=${c.supported}'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeSnapshot {
  final bool isAvailable;
  final String version;
  final List<NativeRuntimeCapability> capabilities;

  const _RuntimeSnapshot({
    required this.isAvailable,
    required this.version,
    required this.capabilities,
  });
}
