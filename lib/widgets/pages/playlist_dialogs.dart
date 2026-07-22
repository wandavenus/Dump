import 'package:flutter/material.dart';

class PlaylistRenameDialog extends StatelessWidget {
  final TextEditingController controller;

  const PlaylistRenameDialog({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Ganti Nama'),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: colors.onSurface),
        decoration: const InputDecoration(
          hintText: 'Nama playlist',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class PlaylistDeleteDialog extends StatelessWidget {
  final String name;

  const PlaylistDeleteDialog({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Hapus Playlist?'),
      content: Text(
        'Playlist "$name" akan dihapus permanen.',
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Hapus',
            style: TextStyle(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
