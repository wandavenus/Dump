import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

Future<String?> showRenamePlaylistDialog({
  required BuildContext context,
  required TextEditingController controller,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final colors = Theme.of(ctx).colorScheme;

      final l = ctx.l10n;
      return AlertDialog(
        title: Text(l.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.onSurface),
          decoration: InputDecoration(
            hintText: l.playlistNameHint,
            hintStyle: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.save),
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

          final l = ctx.l10n;
          return AlertDialog(
            title: Text(l.deletePlaylistConfirm),
            content: Text(
              l.deletePlaylistBody(name),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l.delete,
                  style: TextStyle(color: colors.primary),
                ),
              ),
            ],
          );
        },
      ) ??
      false;
}
