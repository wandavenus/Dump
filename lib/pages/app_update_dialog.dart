import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/pages/app_update_page.dart';
import 'package:musicplayer/services/app_update_service.dart';
import 'package:musicplayer/theme/app_colors.dart';

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo update,
  VoidCallback? onOpenChangelog,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Pembaruan tersedia',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _AppUpdateDialog(
        update: update,
        onOpenChangelog: onOpenChangelog,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AppUpdateDialog extends StatelessWidget {
  final AppUpdateInfo update;
  final VoidCallback? onOpenChangelog;

  const _AppUpdateDialog({
    required this.update,
    this.onOpenChangelog,
  });

  List<String> _changeItems() {
    final lines = update.changelog
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^[-*•+]\s*'), '')
              .replaceAll(RegExp(r'[_#]'), ''),
        )
        .where((line) => line.isNotEmpty)
        .toList();

    return lines.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final changes = _changeItems();

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.075)
                        : Colors.white.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.78),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.42 : 0.16,
                        ),
                        blurRadius: 38,
                        spreadRadius: 2,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18B957).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF18B957).withValues(alpha: 0.24),
                          ),
                        ),
                        child: const Text(
                          'Pembaruan tersedia',
                          style: TextStyle(
                            color: Color(0xFF19C95F),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Versi \${update.version}',
                        style: TextStyle(
                          color: colors.primaryLabel,
                          fontSize: 36,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1.3,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        update.releaseName.isEmpty
                            ? 'Pembaruan terbaru'
                            : update.releaseName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                      if (changes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          height: 1,
                          color: colors.separator.withValues(alpha: 0.42),
                        ),
                        const SizedBox(height: 18),
                        ...changes.map(
                          (change) => Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: colors.primaryLabel,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    change,
                                    style: TextStyle(
                                      color: colors.primaryLabel,
                                      fontSize: 16,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AppUpdaterPage(
                                  initialUpdate: update,
                                  onOpenChangelog: onOpenChangelog,
                                ),
                              ),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF18B957),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Perbarui Sekarang',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Nanti',
                            style: TextStyle(
                              color: colors.secondaryLabel,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
