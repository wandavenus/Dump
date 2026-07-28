part of '../player_song_info_sheet.dart';

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// A collapsible variant of [_InfoSection] for secondary/rarely-needed
/// metadata (raw tags, credits, etc.) — keeps the sheet scannable while
/// still surfacing everything the file actually contains.
///
/// Starts collapsed. Renders nothing if [children] is empty, so callers
/// can build their child list unconditionally and let this widget decide
/// whether the section is worth showing.
class _CollapsibleSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _CollapsibleSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        iconColor: Theme.of(context).colorScheme.primary,
        collapsedIconColor: AppColors.of(context).tertiaryLabel,
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        children: children,
      ),
    );
  }
}
