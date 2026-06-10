import 'package:flutter/material.dart';
import 'package:musicplayer/themes/apple_music_material.dart';
import 'package:musicplayer/themes/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: AppleMusicPageBackground(
        child: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: ThemeController.glassTheme,
            builder: (context, isGlass, _) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  AppleMusicMaterial(
                    borderRadius: BorderRadius.circular(22),
                    style: AppleMusicMaterialStyle.thin,
                    showShadow: false,
                    child: SwitchListTile(
                      title: const Text(
                        'Apple Music Glass Theme',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Uses the shared iOS-style material system.',
                        style: TextStyle(color: AppleMusicColors.secondaryText),
                      ),
                      activeColor: AppleMusicColors.accent,
                      value: isGlass,
                      onChanged: ThemeController.setGlassTheme,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AppleMusicMaterial(
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                    style: AppleMusicMaterialStyle.thin,
                    showShadow: false,
                    child: ListTile(
                      title: Text(
                        'Tentang',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
