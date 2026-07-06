import 'package:flutter/material.dart';

import '../services/media_store_service.dart';

class CommonActions extends StatefulWidget {
  const CommonActions({super.key});

  @override
  State<CommonActions> createState() => _CommonActionsState();
}

class _CommonActionsState extends State<CommonActions> {
  bool _scanning = false;

  Future<void> _rescan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final songs = await MediaStoreService.refreshSongs();
      MediaStoreService.rescanNotifier.value++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ditemukan ${songs.length} lagu'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1C1C1E),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal scan lagu'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1C1C1E),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _cast(BuildContext context) {
    // TODO: Cast function
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, 0),
          child: IconButton(
            onPressed: () => _cast(context),
            icon: const Icon(
              Icons.cast_outlined,
              color: Color(0xFFF92D48),
              size: 24,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, 0),
          child: PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: Color(0xFFF92D48),
              size: 24,
            ),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.of(context, rootNavigator: true)
                    .pushNamed('/settings');
              } else if (value == 'rescan') {
                _rescan();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'rescan',
                child: Row(
                  children: [
                    _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFF92D48),
                            ),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: 12),
                    const Text('Scan Ulang Lagu'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 18),
                    SizedBox(width: 12),
                    Text('Pengaturan'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
