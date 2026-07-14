part of '../settings_page.dart';

// ─── Tentang App ────────────────────────────────────────────────────────────
//
// Berisi info aplikasi (nama, developer, versi) yang sebelumnya tampil
// langsung di section "Tentang". Ketuk "Versi" 5x dalam 2 detik untuk
// mengaktifkan Mode Debug (lihat _VersionTile / _DebugState).

class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scroll.offset;
    if ((offset - _offset).abs() > 0.5) {
      setState(() => _offset = offset);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Tentang App',
        scrollOffset: _offset,
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
      body: SingleChildScrollView(
        controller: _scroll,
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LargePageTitle(title: 'Tentang App'),
            const HeaderDivider(),
            const SizedBox(height: 6),
            const SettingsInfoRow(
              title: 'Music Player',
              trailing: 'Wndavenznchole',
            ),
            const SettingsDivider(),
            _VersionTile(),
            const SettingsDivider(),
          ],
        ),
      ),
    );
  }
}
