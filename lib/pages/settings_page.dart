import 'package:flutter/material.dart';
import 'package:musicplayer/themes/theme_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text(
              'Glass Theme',
              style: TextStyle(color: Colors.white),
            ),
            value: ThemeController.glassTheme,
            onChanged: (value) {
              setState(() {
                ThemeController.glassTheme = value;
              });
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
      ),
    );
  }
}
