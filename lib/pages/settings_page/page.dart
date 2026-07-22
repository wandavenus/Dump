part of '../settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scroll.offset;
    if ((offset - _offsetNotifier.value).abs() > 0.5) {
      _offsetNotifier.value = offset;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: 'Pengaturan',
        scrollOffsetListenable: _offsetNotifier,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
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
            const LargePageTitle(title: 'Pengaturan'),
            const HeaderDivider(),
            _SettingsBody(),
          ],
        ),
      ),
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────
