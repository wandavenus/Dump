part of '../library_sections.dart';

class _LibraryHeader extends StatelessWidget {
  final bool editMode;
  final VoidCallback onToggleEdit;

  const _LibraryHeader({required this.editMode, required this.onToggleEdit});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.libraryTitle,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: c.primaryLabel,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: GestureDetector(
              onTap: onToggleEdit,
              child: Text(
                editMode ? context.l10n.done : context.l10n.edit,
                style: TextStyle(
                  color: editMode
                      ? c.primaryLabel.withValues(alpha: 0.7)
                      : const Color(0xFFF92D48),
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Row Normal ────────────────────────────────────────────────────────────────
