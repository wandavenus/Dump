part of '../settings_page.dart';

// ─── Shared empty placeholder scaffold ─────────────────────────────────────
//
// Digunakan oleh page-page baru di section "Tentang" (Changelog, Laporkan
// Bug, Dukungan) sebelum kontennya diisi.

class _EmptyPlaceholderPage extends StatelessWidget {
  final String title;
  const _EmptyPlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: title,
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [],
      ),
      body: Center(
        child: Text(
          context.l10n.contentUnavailable,
          style: TextStyle(color: c.secondaryLabel, fontSize: 15),
        ),
      ),
    );
  }
}
