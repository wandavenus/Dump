import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:musicplayer/pages/settings_page.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/utils/zoom_fade_route.dart';

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
            content: Text(context.l10n.songsFoundMsg(songs.length)),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.of(context).surface,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.scanFailed),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.of(context).surface,
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
              CupertinoIcons.ellipsis_vertical,
              color: Color(0xFFF92D48),
              size: 23,
            ),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.of(context, rootNavigator: true).push(
                  ZoomFadeRoute(page: const SettingsPage()),
                );
              } else if (value == 'rescan') {
                _rescan();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'rescan',
                child: Text(context.l10n.rescanSongs),
              ),
              PopupMenuItem<String>(
                value: 'settings',
                child: Text(context.l10n.settings),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
