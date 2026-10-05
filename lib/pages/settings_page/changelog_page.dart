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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: context.l10n.changelogTitle,
        scrollOffsetListenable: _offsetNotifier,
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
      body: _changelogEntries.isEmpty
          ? Center(
              child: Text(
                context.l10n.noChangelog,
                style: TextStyle(
                  color: AppColors.of(context).secondaryLabel,
                  fontSize: 15,
                ),
              ),
            )
          : SingleChildScrollView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LargePageTitle(title: context.l10n.changelogTitle),
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

class _ChangelogEntryTile extends StatefulWidget {
  final _ChangelogEntry entry;
  const _ChangelogEntryTile({required this.entry});

  @override
  State<_ChangelogEntryTile> createState() => _ChangelogEntryTileState();
}

class _ChangelogEntryTileState extends State<_ChangelogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final entry = widget.entry;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'v${entry.version}',
                      style: TextStyle(
                        color: c.primaryLabel,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      color: c.secondaryLabel,
                      size: 17,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_expanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.date,
                              style: TextStyle(
                                color: c.secondaryLabel,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final change in entry.changes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '•  ',
                                      style: TextStyle(
                                        color: c.secondaryLabel,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        change,
                                        style: TextStyle(
                                          color: c.primaryLabel.withValues(
                                            alpha: 0.87,
                                          ),
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
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
