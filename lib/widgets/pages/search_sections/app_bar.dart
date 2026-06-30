part of '../search_sections.dart';

class _SearchAppBar extends StatelessWidget {
  const _SearchAppBar({required this.scrollOffset});

  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.black,
      automaticallyImplyLeading: false,
      surfaceTintColor: Colors.transparent,
      title: Transform.translate(
        offset: Offset(
          0,
          (1 - (scrollOffset / 100).clamp(0.0, 1.0).toDouble()) * 40,
        ),
        child: Opacity(
          opacity:
              ((((scrollOffset - 25) / 25).clamp(0.0, 1.0).toDouble()) * 1.5)
                  .clamp(0.0, 1.0)
                  .toDouble(),
          child: const Text(
            'Cari',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0).toDouble(),
          child: Container(height: 0.9, color: const Color(0xFF48484A)),
        ),
      ),
      actions: const [CommonActions()],
    );
  }
}

// ─── Title ────────────────────────────────────────────────────────────────────
