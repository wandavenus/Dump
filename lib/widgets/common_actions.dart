import 'package:flutter/material.dart';
import 'package:musicplayer/themes/apple_music_blur.dart';

class CommonActions extends StatelessWidget {
  const CommonActions({super.key});

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
              color: AppleMusicColors.accent,
              size: 24,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, 0),
          child: PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppleMusicColors.accent,
              size: 24,
            ),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.pushNamed(context, '/settings');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'settings',
                child: Text('Pengaturan'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
