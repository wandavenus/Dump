part of '../settings_page.dart';

// ─── Changelog ──────────────────────────────────────────────────────────────
//
// Menampilkan riwayat perubahan app dari _changelogEntries (lihat
// changelog_data.dart). Setiap pengerjaan baru WAJIB menambah entri di sana.

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
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
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Changelog',
        scrollOffsetListenable: _offsetNotifier,
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
      body: _changelogEntries.isEmpty
          ? const Center(
              child: Text(
                'Belum ada perubahan tercatat',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
              ),
            )
          : SingleChildScrollView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LargePageTitle(title: 'Changelog'),
                  const HeaderDivider(),
                  const SizedBox(height: 6),
                  for (final entry in _changelogEntries) ...[
                    _ChangelogEntryTile(entry: entry),
                    const SettingsDivider(),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ChangelogEntryTile extends StatelessWidget {
  final _ChangelogEntry entry;
  const _ChangelogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'v${entry.version}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.date,
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final change in entry.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
                  ),
                  Expanded(
                    child: Text(
                      change,
                      style: const TextStyle(
                        color: Color(0xFFEBEBF0),
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
