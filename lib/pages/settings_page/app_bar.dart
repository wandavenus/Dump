part of '../settings_page.dart';

class _SettingsAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      pinned: true,
      expandedHeight: 100,
      collapsedHeight: kToolbarHeight,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final expandRatio = ((constraints.maxHeight - kToolbarHeight) /
                  (100 - kToolbarHeight))
              .clamp(0.0, 1.0)
              .toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              Positioned(
                bottom: 13,
                left: 16,
                child: Opacity(
                  opacity: expandRatio,
                  child: Text(
                    'Pengaturan',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(expandRatio),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0).toDouble(),
                  child: const Center(
                    child: Text(
                      'Pengaturan',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 0.5,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0).toDouble(),
                  child: Container(color: const Color(0xFF38383A)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────
