part of '../settings_page.dart';

// ─── Comprehensive log viewer bottom sheet ─────────────────────────────────────

class _LogViewerSheet extends StatefulWidget {
  const _LogViewerSheet();

  @override
  State<_LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<_LogViewerSheet> {
  String?   _filterCategory;
  LogLevel? _filterMinLevel;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, sc) {
        final logs = LogService.getLogs(
          category: _filterCategory,
          minLevel: _filterMinLevel,
        ).reversed.toList();

        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // ── Header row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Log Aktivitas',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(
                    '${logs.length}',
                    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                  const Spacer(),
                  _LVIconBtn(
                    icon: Icons.copy_outlined,
                    tooltip: 'Salin semua',
                    onTap: _copyLogs,
                  ),
                  _LVIconBtn(
                    icon: Icons.delete_outline,
                    tooltip: 'Hapus log',
                    onTap: () { LogService.clear(); setState(() {}); },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Level filter ────────────────────────────────────────────
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _LVChip(
                    label: 'Semua',
                    selected: _filterMinLevel == null,
                    onTap: () => setState(() => _filterMinLevel = null),
                  ),
                  for (final lvl in LogLevel.values)
                    _LVChip(
                      label: lvl.prefix,
                      selected: _filterMinLevel == lvl,
                      color: _lvlColor(lvl),
                      onTap: () => setState(() => _filterMinLevel = lvl),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── Category filter ─────────────────────────────────────────
            ValueListenableBuilder<int>(
              valueListenable: LogService.logCount,
              builder: (_, __, ___) {
                final cats = LogService.categories;
                if (cats.isEmpty) return const SizedBox(height: 4);
                return SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _LVChip(
                        label: 'Semua',
                        selected: _filterCategory == null,
                        onTap: () => setState(() => _filterCategory = null),
                      ),
                      for (final cat in cats)
                        _LVChip(
                          label: cat,
                          selected: _filterCategory == cat,
                          onTap: () => setState(() => _filterCategory = cat),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: Color(0xFF38383A)),

            // ── Log list ────────────────────────────────────────────────
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text('Belum ada log',
                          style: TextStyle(color: Color(0xFF8E8E93))),
                    )
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: logs.length,
                      itemBuilder: (_, i) => _LogEntryTile(entry: logs[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _copyLogs() {
    final all = LogService.getLogs(
      category: _filterCategory,
      minLevel: _filterMinLevel,
    ).map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: all));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log disalin ke clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static Color _lvlColor(LogLevel lvl) => switch (lvl) {
    LogLevel.verbose => const Color(0xFF8E8E93),
    LogLevel.debug   => const Color(0xFF30D158),
    LogLevel.info    => Colors.white70,
    LogLevel.warning => Colors.orange,
    LogLevel.error   => const Color(0xFFF92D48),
  };
}

// ─── Log entry tile ────────────────────────────────────────────────────────────

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = _lvlColor(entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 6),
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        entry.level.prefix,
                        style: TextStyle(
                          color: c, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '[${entry.category}]',
                      style: TextStyle(
                        color: c.withOpacity(0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.timestampMs,
                      style: const TextStyle(
                          color: Color(0xFF48484A), fontSize: 10),
                    ),
                    if (entry.elapsed != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '+${entry.elapsed!.inMilliseconds}ms',
                        style: const TextStyle(
                            color: Color(0xFF636366), fontSize: 10),
                      ),
                    ],
                  ],
                ),
                Text(
                  entry.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (entry.extra != null && entry.extra!.isNotEmpty)
                  Text(
                    entry.extra.toString(),
                    style: const TextStyle(
                        color: Color(0xFF636366), fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _lvlColor(LogLevel lvl) => switch (lvl) {
    LogLevel.verbose => const Color(0xFF8E8E93),
    LogLevel.debug   => const Color(0xFF30D158),
    LogLevel.info    => Colors.white70,
    LogLevel.warning => Colors.orange,
    LogLevel.error   => const Color(0xFFF92D48),
  };
}

// ─── Reusable chip & icon-button for this viewer ──────────────────────────────

class _LVChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _LVChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.18) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: c.withOpacity(0.5)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : const Color(0xFF8E8E93),
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LVIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _LVIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: const Color(0xFF8E8E93), size: 18),
        ),
      ),
    );
  }
}
