import 'package:flutter/material.dart';
import 'package:musicplayer/themes/apple_music_blur.dart';
import 'package:musicplayer/themes/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
  flexibleSpace: const AppleMusicBarBackground(),
        title: const Text('Pengaturan'),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: ThemeController.glassTheme,
        builder: (context, isGlass, _) {
          return ListView(
            children: [
              SwitchListTile(
                title: const Text(
                  'Glass Theme',
                  style: TextStyle(color: Colors.white),
                ),
                value: isGlass,
                onChanged: (value) {
                  ThemeController.setGlassTheme(value);
                },
              ),
              const Divider(height: 1),
              const ListTile(
                title: Text(
                  'Tentang',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const Divider(height: 1),
            ],
          );
        },
      ),
    );
  }
}
