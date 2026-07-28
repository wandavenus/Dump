part of '../search_sections.dart';

class _SearchTitle extends StatelessWidget {
  final bool isSearching;
  const _SearchTitle({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSearching ? 0 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          context.l10n.searchTitle,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: c.primaryLabel,
          ),
        ),
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────
