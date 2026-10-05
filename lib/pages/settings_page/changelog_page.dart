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
  final Set<String> _expandedVersions = <String>{};

  void _toggleVersion(String version) {
    setState(() {
      if (!_expandedVersions.add(version)) {
        _expandedVersions.remove(version);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        title: Text(
          context.l10n.changelogTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
          ),
        ),
        centerTitle: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: _changelogEntries.isEmpty
          ? Center(
              child: Text(
                context.l10n.noChangelog,
                style: TextStyle(
                  color: c.secondaryLabel,
                  fontSize: 15,
                ),
              ),
            )
          : ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(top: 6),
              itemCount: _changelogEntries.length,
              separatorBuilder: (_, _) => const SettingsDivider(),
              itemBuilder: (context, index) {
                final entry = _changelogEntries[index];
                return _ChangelogEntryTile(
                  entry: entry,
                  expanded: _expandedVersions.contains(entry.version),
                  onToggle: () => _toggleVersion(entry.version),
                );
              },
            ),
    );
  }
}

class _ChangelogEntryTile extends StatelessWidget {
  final _ChangelogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _ChangelogEntryTile({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'v${entry.version}',
                      style: TextStyle(
                        color: c.primaryLabel,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.date,
                      style: TextStyle(
                        color: c.secondaryLabel,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                minimumSize: Size.zero,
                onPressed: onToggle,
                child: AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    color: c.secondaryLabel,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final change in entry.changes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        color: c.primaryLabel.withValues(alpha: 0.87),
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
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
