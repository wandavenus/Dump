import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
        children: const [
          ListTile(
            title: Text(
              'Tema',
              style: TextStyle(color: Colors.white),
            ),
          ),
          Divider(height: 1),

          ListTile(
            title: Text(
              'Tentang',
              style: TextStyle(color: Colors.white),
            ),
          ),
          Divider(height: 1),
        ],
      ),
    );
  }
}