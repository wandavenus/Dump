import 'package:flutter/material.dart';
import 'package:musicplayer/themes/apple_music_blur.dart';

class CommonActions extends StatelessWidget {
  const CommonActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -0.5),
          child: IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.cast_outlined,
              color: AppleMusicColors.accent,
              size: 24,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -0.5),
          child: PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppleMusicColors.accent,
              size: 24,
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
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
