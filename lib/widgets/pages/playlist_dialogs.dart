import 'package:flutter/material.dart';

Future<String?> showRenamePlaylistDialog({
  required BuildContext context,
  required TextEditingController controller,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final colors = Theme.of(ctx).colorScheme;

      return AlertDialog(
        title: const Text('Ganti Nama'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.onSurface),
          decoration: InputDecoration(
            hintText: 'Nama playlist',
            hintStyle: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  );
}

Future<bool> showDeletePlaylistDialog({
  required BuildContext context,
  required String name,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final colors = Theme.of(ctx).colorScheme;

          return AlertDialog(
            title: const Text('Hapus Playlist?'),
            content: Text(
              'Playlist "$name" akan dihapus permanen.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Hapus',
                  style: TextStyle(color: colors.primary),
                ),
              ),
            ],
          );
        },
      ) ??
      false;
}
