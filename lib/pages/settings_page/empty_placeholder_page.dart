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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: title,
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [],
      ),
      body: const Center(
        child: Text(
          'Belum ada konten',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
        ),
      ),
    );
  }
}
