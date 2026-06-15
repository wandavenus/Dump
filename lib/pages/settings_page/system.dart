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

        // Logging toggle
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

        // Errors only toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, logEnabled, _) => ValueListenableBuilder<bool>(
            valueListenable: LogService.errorsOnly,
            builder: (_, errOnly, _) => SettingsToggleRow(
              title: 'Error & Peringatan Saja',
              subtitle: 'Sembunyikan log info & verbose',
              value: errOnly,
              onChanged: (v) async {
                if (logEnabled) await LogService.setErrorsOnly(v);
              },
            ),
          ),
        ),
        const SettingsDivider(),

        // Verbose toggle
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

        // Log viewer button
        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, _) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),

        // Clear logs
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
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _LogViewerModal(),
    );
  }
}

// ─── Log viewer modal (live-updating, searchable, filterable) ─────────────────

class _LogViewerModal extends StatefulWidget {
  const _LogViewerModal();

  @override
  State<_LogViewerModal> createState() => _LogViewerModalState();
}

class _LogViewerModalState extends State<_LogViewerModal> {
  LogLevel? _levelFilter;
  String? _categoryFilter;
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
      builder: (context, _, __) {
        final search = _searchCtrl.text;
        final allLogs = LogService.getLogs(
          level: _levelFilter,
          category: _categoryFilter,
          search: search.isEmpty ? null : search,
        );
        final reversed = allLogs.reversed.toList();
        final categories = LogService.getCategories();

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (context, sc) => Column(
            children: [
              // ── Handle + header ──────────────────────────────────────────
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Log Aktivitas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${reversed.length}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    // Copy all button
                    GestureDetector(
                      onTap: () => _copyAll(reversed),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded,
                                color: Colors.white54, size: 14),
                            SizedBox(width: 4),
                            Text('Salin',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Search field ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.search_rounded,
                          color: Colors.white38, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Cari pesan atau kategori...',
                            hintStyle:
                                TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
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
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.close_rounded,
                                color: Colors.white38, size: 16),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── Level filter chips ────────────────────────────────────────
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _levelChip(null, 'Semua', Colors.white38),
                    const SizedBox(width: 6),
                    _levelChip(LogLevel.error, 'ERR',
                        const Color(0xFFF92D48)),
                    const SizedBox(width: 6),
                    _levelChip(
                        LogLevel.warning, 'WRN', Colors.orange),
                    const SizedBox(width: 6),
                    _levelChip(LogLevel.info, 'INF',
                        const Color(0xFF30D158)),
                    const SizedBox(width: 6),
                    _levelChip(LogLevel.verbose, 'VRB',
                        const Color(0xFF636366)),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // ── Category filter chips ─────────────────────────────────────
              if (categories.isNotEmpty)
                SizedBox(
                  height: 28,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _categoryChip(null, 'Semua'),
                      ...categories.map((c) => Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _categoryChip(c, c),
                          )),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              const Divider(
                  color: Color(0xFF38383A), height: 1, thickness: 0.5),

              // ── Log list ─────────────────────────────────────────────────
              Expanded(
                child: reversed.isEmpty
                    ? const Center(
                        child: Text(
                          'Tidak ada log',
                          style: TextStyle(color: Color(0xFF8E8E93)),
                        ),
                      )
                    : ListView.separated(
                        controller: sc,
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                        itemCount: reversed.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: Color(0xFF38383A),
                          height: 1,
                          thickness: 0.3,
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (_, i) {
                          final entry = reversed[i];
                          final hasStack = entry.stackTrace != null &&
                              entry.stackTrace!.isNotEmpty;
                          final expanded = _expandedIndices.contains(i);

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: hasStack
                                ? () => setState(() {
                                      if (expanded) {
                                        _expandedIndices.remove(i);
                                      } else {
                                        _expandedIndices.add(i);
                                      }
                                    })
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 8),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Level badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _levelColor(entry.level)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          entry.levelTag,
                                          style: TextStyle(
                                            color:
                                                _levelColor(entry.level),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Category
                                      Text(
                                        entry.category,
                                        style: const TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                      // Timestamp with centiseconds
                                      Text(
                                        entry.formattedTime,
                                        style: const TextStyle(
                                          color: Color(0xFF48484A),
                                          fontSize: 10,
                                          fontFeatures: [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                      if (hasStack) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          expanded
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          color: Colors.white24,
                                          size: 14,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.message,
                                    style: TextStyle(
                                      color: entry.level == LogLevel.error
                                          ? const Color(0xFFF92D48)
                                              .withValues(alpha: 0.9)
                                          : entry.level ==
                                                  LogLevel.warning
                                              ? Colors.orange
                                                  .withValues(alpha: 0.9)
                                              : entry.level ==
                                                      LogLevel.verbose
                                                  ? Colors.white30
                                                  : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  // Stack trace (expandable)
                                  if (hasStack && expanded) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.white12,
                                            width: 0.5),
                                      ),
                                      child: Text(
                                        entry.stackTrace!,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _levelChip(LogLevel? level, String label, Color color) {
    final active = _levelFilter == level;
    return GestureDetector(
      onTap: () => setState(() {
        _levelFilter = level;
        _expandedIndices.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? Border.all(color: color.withValues(alpha: 0.6), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.white38,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String? category, String label) {
    final active = _categoryFilter == category;
    return GestureDetector(
      onTap: () => setState(() {
        _categoryFilter = category;
        _expandedIndices.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 0.8)
              : Border.all(color: Colors.transparent, width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white70 : Colors.white38,
            fontSize: 11,
            fontWeight: active ? FontWeight.w500 : FontWeight.normal,
          ),
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
    for (final e in entries.reversed) {
      buf.writeln(e.toString());
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${entries.length} entri log disalin',
          style: const TextStyle(fontSize: 13),
        ),
        backgroundColor: const Color(0xFF2C2C2E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
