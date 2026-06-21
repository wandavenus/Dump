part of '../settings_page.dart';

class _SystemSection extends StatelessWidget {
  const _SystemSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SISTEM'),
        const SizedBox(height: 6),

        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, enabled, _) => SettingsToggleRow(
            title: 'Logging Aktif',
            subtitle: 'Catat aktivitas & error app',
            value: enabled,
            onChanged: LogService.setLoggingEnabled,
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<bool>(
  valueListenable: LogService.loggingEnabled,
  builder: (_, logEnabled, __) => ValueListenableBuilder<bool>(
    valueListenable: LogService.errorsOnly,
    builder: (_, errOnly, __) => SettingsToggleRow(
      title: 'Error & Peringatan Saja',
      subtitle: 'Sembunyikan log info & verbose',
      value: errOnly,
      onChanged: logEnabled
      ? (v) async {
        await LogService.setErrorsOnly(v);
      }
    : (_) async {},
    ),
  ),
),
        const SettingsDivider(),

        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, logEnabled, _) => ValueListenableBuilder<bool>(
            valueListenable: LogService.errorsOnly,
            builder: (_, errOnly, _) => ValueListenableBuilder<bool>(
              valueListenable: LogService.verboseEnabled,
              builder: (_, verbose, _) => SettingsToggleRow(
                title: 'Log Verbose',
                subtitle: 'Tampilkan log detail (seek, speed, dll)',
                value: verbose,
                onChanged: (v) async {
                  if (logEnabled && !errOnly) {
                    await LogService.setVerboseEnabled(v);
                  }
                },
              ),
            ),
          ),
        ),
        const SettingsDivider(),

        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, _) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),

        SettingsActionRow(
          title: 'Bersihkan Log',
          trailing: '',
          onTap: LogService.clear,
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _showLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF080808),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _LogViewerModal(),
    );
  }
}

// ─── Log viewer modal ─────────────────────────────────────────────────────────

class _LogViewerModal extends StatefulWidget {
  const _LogViewerModal();

  @override
  State<_LogViewerModal> createState() => _LogViewerModalState();
}

class _LogViewerModalState extends State<_LogViewerModal> {
  LogLevel? _levelFilter;
  String?   _categoryFilter;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _expandedIndices = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LogService.logCount,
      builder: (context, _, _) {
        final search  = _searchCtrl.text;
        final allLogs = LogService.getLogs(
          level:    _levelFilter,
          category: _categoryFilter,
          search:   search.isEmpty ? null : search,
        );
        final reversed   = allLogs.reversed.toList();
        final categories = LogService.getCategories();

        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize:     1.0,
          minChildSize:     0.4,
          expand:           false,
          builder: (context, sc) => Column(
            children: [
              // ── Handle ───────────────────────────────────────────────────
              const SizedBox(height: 10),
              Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Log',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${reversed.length}',
                      style: const TextStyle(
                        color: Color(0xFF48484A),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    // Error / warning badge summary
                    _LevelBadge(
                      count: LogService.countByLevel(LogLevel.error),
                      color: const Color(0xFFF92D48),
                    ),
                    const SizedBox(width: 6),
                    _LevelBadge(
                      count: LogService.countByLevel(LogLevel.warning),
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    // Copy button
                    GestureDetector(
                      onTap: () => _copyAll(reversed),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, color: Color(0xFF636366), size: 13),
                            SizedBox(width: 5),
                            Text(
                              'salin',
                              style: TextStyle(
                                color: Color(0xFF636366),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Search ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF3A3A3C), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                          color: Color(0xFFAEAEB2),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          hintText: 'filter...',
                          hintStyle: TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          border:          InputBorder.none,
                          isDense:         true,
                          contentPadding:  EdgeInsets.zero,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF3A3A3C),
                          size: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Filter tabs — level + categories in one scroll row ───────
              SizedBox(
                height: 22,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _levelTab(null,              'ALL'),
                    _levelTab(LogLevel.error,    'ERR'),
                    _levelTab(LogLevel.warning,  'WRN'),
                    _levelTab(LogLevel.info,     'INF'),
                    _levelTab(LogLevel.verbose,  'VRB'),
                    if (categories.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '│',
                          style: TextStyle(
                            color: Color(0xFF2C2C2E),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      ...categories.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: _catTab(c),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 6),
              Container(height: 0.5, color: const Color(0xFF1C1C1E)),

              // ── Log list ─────────────────────────────────────────────────
              Expanded(
                child: reversed.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isNotEmpty ||
                                  _levelFilter != null ||
                                  _categoryFilter != null
                              ? 'tidak ada hasil'
                              : 'belum ada log',
                          style: const TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: sc,
                        padding:    const EdgeInsets.only(bottom: 40),
                        itemCount:  reversed.length,
                        itemBuilder: (_, i) => _buildEntry(reversed[i], i),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Entry row ──────────────────────────────────────────────────────────────

  Widget _buildEntry(LogEntry entry, int i) {
    final hasStack = entry.stackTrace != null && entry.stackTrace!.isNotEmpty;
    final expanded = _expandedIndices.contains(i);
    final barColor = _levelColor(entry.level);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasStack
          ? () => setState(() {
                if (expanded) _expandedIndices.remove(i);
                else _expandedIndices.add(i);
              })
          : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Left level color bar ──────────────────────────────────────
            Container(
              width: 2.5,
              color: barColor.withValues(alpha: 0.55),
            ),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta: category + timestamp
                    Row(
                      children: [
                        Text(
                          entry.category,
                          style: TextStyle(
                            color: barColor.withValues(alpha: 0.5),
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          entry.formattedTime,
                          style: const TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (hasStack) ...[
                          const SizedBox(width: 4),
                          Icon(
                            expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: const Color(0xFF3A3A3C),
                            size: 12,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Message
                    Text(
                      entry.message,
                      style: TextStyle(
                        color: switch (entry.level) {
                          LogLevel.error   => const Color(0xFFF92D48).withValues(alpha: 0.85),
                          LogLevel.warning => Colors.orange.withValues(alpha: 0.85),
                          LogLevel.verbose => const Color(0xFF48484A),
                          _                => const Color(0xFFAEAEB2),
                        },
                        fontSize:   11.5,
                        fontFamily: 'monospace',
                        height:     1.45,
                      ),
                    ),

                    // Stack trace (expandable)
                    if (hasStack && expanded) ...[
                      const SizedBox(height: 6),
                      Container(
                        width:   double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:        const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(4),
                          border:       Border(
                            left: BorderSide(
                              color: barColor.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          entry.stackTrace!,
                          style: const TextStyle(
                            color:      Color(0xFF636366),
                            fontSize:   9.5,
                            fontFamily: 'monospace',
                            height:     1.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter tab helpers ─────────────────────────────────────────────────────

  Widget _levelTab(LogLevel? level, String label) {
    final active = _levelFilter == level;
    final color  = level == null ? Colors.white : _levelColor(level);
    return GestureDetector(
      onTap: () => setState(() {
        _levelFilter = level;
        _expandedIndices.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Text(
          label,
          style: TextStyle(
            color:      active ? color : const Color(0xFF48484A),
            fontSize:   11,
            fontFamily: 'monospace',
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _catTab(String category) {
    final active = _categoryFilter == category;
    return GestureDetector(
      onTap: () => setState(() {
        _categoryFilter = active ? null : category;
        _expandedIndices.clear();
      }),
      child: Text(
        category,
        style: TextStyle(
          color:      active ? const Color(0xFFAEAEB2) : const Color(0xFF48484A),
          fontSize:   11,
          fontFamily: 'monospace',
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Color _levelColor(LogLevel level) => switch (level) {
        LogLevel.error   => const Color(0xFFF92D48),
        LogLevel.warning => Colors.orange,
        LogLevel.info    => const Color(0xFF30D158),
        LogLevel.verbose => const Color(0xFF636366),
      };

  void _copyAll(List<LogEntry> entries) {
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln(e.toString());
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${entries.length} entri disalin',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        behavior:        SnackBarBehavior.floating,
        duration:        const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ── Small error/warning count badge in header ──────────────────────────────

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.count, required this.color});

  final int   count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color:      color.withValues(alpha: 0.8),
          fontSize:   10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
