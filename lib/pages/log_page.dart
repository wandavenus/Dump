import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicplayer/services/log_service.dart';

// TODO(refactor): LogPage is 889 lines — god file. Future split boundaries:
//   1. _LogPageState (state + filtering logic) → log_page/state.dart
//   2. _LogEntryTile (entry renderer) → log_page/entry_tile.dart
//   3. Filter bar / search bar widgets → log_page/filter_bar.dart

part 'log_page/bar_btn.dart';
part 'log_page/app_bar_badge.dart';

/// Full-screen developer log viewer.
/// Dibuka via Navigator.push dari Settings → Log Aktivitas.
/// Opsional: [initialCategory] untuk langsung memfilter ke kategori tertentu
/// saat dibuka.
class LogPage extends StatefulWidget {
  const LogPage({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  LogLevel? _levelFilter;
  String?   _categoryFilter;
  bool      _liveTail = true; // auto-scroll ke entri terbaru

  final TextEditingController _searchCtrl  = TextEditingController();
  final ScrollController      _scrollCtrl  = ScrollController();
  final Set<int>              _expanded    = {};

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Pre-set filter kategori kalau dipassing dari caller (mis. Debug Section).
    _categoryFilter = widget.initialCategory;
    LogService.logCount.addListener(_onNewLog);
  }

  @override
  void dispose() {
    LogService.logCount.removeListener(_onNewLog);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    setState(_expanded.clear);
    if (_liveTail && _scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Data helpers ────────────────────────────────────────────────────────────

  List<LogEntry> get _filtered => LogService.getLogs(
        level:    _levelFilter,
        category: _categoryFilter,
        search:   _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
      ).reversed.toList();

  int _countLevel(LogLevel l) => LogService.countByLevel(l);

  Color _levelColor(LogLevel l) => switch (l) {
        LogLevel.error   => const Color(0xFFF92D48),
        LogLevel.warning => const Color(0xFFFF9F0A),
        LogLevel.info    => const Color(0xFF30D158),
        LogLevel.verbose => const Color(0xFF636366),
      };

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _copyAll(List<LogEntry> entries) {
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln(e.toString());
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _snack('${entries.length} entri disalin');
  }

  void _copyEntry(LogEntry e) {
    Clipboard.setData(ClipboardData(text: e.toString()));
    _snack('Entri disalin');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      backgroundColor: const Color(0xFF1C1C1E),
      behavior:        SnackBarBehavior.floating,
      duration:        const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _jumpTop() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _jumpBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _clearLogs() {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Hapus semua log?',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(color: Color(0xFF636366))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus',
                style: TextStyle(color: Color(0xFFF92D48))),
          ),
        ],
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed == true) {
        LogService.clear();
        setState(_expanded.clear);
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final entries    = _filtered;
    final categories = LogService.getCategories();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(entries),
      body: Column(
        children: [
          _buildSearch(),
          _buildFilterRow(categories),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFF1C1C1E)),
          Expanded(child: _buildList(entries)),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(entries, safeBottom),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(List<LogEntry> entries) {
    final errCount  = _countLevel(LogLevel.error);
    final warnCount = _countLevel(LogLevel.warning);

    return AppBar(
      backgroundColor:  Colors.black,
      foregroundColor:  Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      leading: const BackButton(),
      title: Row(
        children: [
          const Text(
            'Log',
            style: TextStyle(
              fontSize:   17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entries.length}',
            style: const TextStyle(
              color:      Color(0xFF48484A),
              fontSize:   12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 10),
          if (errCount > 0) _AppBarBadge(count: errCount, color: const Color(0xFFF92D48)),
          if (errCount > 0 && warnCount > 0) const SizedBox(width: 5),
          if (warnCount > 0) _AppBarBadge(count: warnCount, color: const Color(0xFFFF9F0A)),
        ],
      ),
      actions: [
        // Logging level button — dipindah dari Settings › Sistem
        // (dulu 3 toggle terpisah: Logging Aktif / Error & Peringatan Saja /
        // Log Verbose), sekarang satu tombol yang membuka pemilih level.
        _buildLogLevelButton(),
        const SizedBox(width: 4),
        // Live tail toggle
        GestureDetector(
          onTap: () => setState(() => _liveTail = !_liveTail),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _liveTail
                    ? const Color(0xFF30D158).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 7,
                    color: _liveTail
                        ? const Color(0xFF30D158)
                        : const Color(0xFF48484A),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: _liveTail
                          ? const Color(0xFF30D158)
                          : const Color(0xFF48484A),
                      fontSize:   10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Log level button (menggantikan 3 toggle Settings › Sistem) ──────────────

  ({String label, Color color, IconData icon}) _logLevelVisual() {
    if (!LogService.loggingEnabled.value) {
      return (label: 'OFF', color: const Color(0xFF48484A), icon: Icons.tune_rounded);
    }
    if (LogService.errorsOnly.value) {
      return (label: 'ERR', color: const Color(0xFFFF9F0A), icon: Icons.tune_rounded);
    }
    if (LogService.verboseEnabled.value) {
      return (label: 'VRB', color: const Color(0xFF0A84FF), icon: Icons.tune_rounded);
    }
    return (label: 'LOG', color: const Color(0xFF30D158), icon: Icons.tune_rounded);
  }

  Widget _buildLogLevelButton() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        LogService.loggingEnabled,
        LogService.errorsOnly,
        LogService.verboseEnabled,
      ]),
      builder: (_, _) {
        final v = _logLevelVisual();
        return GestureDetector(
          onTap: _showLogLevelSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:        v.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(v.icon, size: 11, color: v.color),
                  const SizedBox(width: 4),
                  Text(
                    v.label,
                    style: TextStyle(
                      color:      v.color,
                      fontSize:   10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogLevelSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            LogService.loggingEnabled,
            LogService.errorsOnly,
            LogService.verboseEnabled,
          ]),
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Level Log',
                  style: TextStyle(
                    color:      Colors.white,
                    fontSize:   15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _logLevelOption(
                title:    'Nonaktif',
                subtitle: 'Logging dimatikan',
                selected: !LogService.loggingEnabled.value,
                onTap:    () => LogService.setLoggingEnabled(false),
              ),
              _logLevelOption(
                title:    'Error & Peringatan Saja',
                subtitle: 'Sembunyikan log info & verbose',
                selected: LogService.loggingEnabled.value &&
                    LogService.errorsOnly.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(true);
                },
              ),
              _logLevelOption(
                title:    'Normal',
                subtitle: 'Log info, error & peringatan',
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    !LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(false);
                },
              ),
              _logLevelOption(
                title:    'Log Verbose',
                subtitle: 'Tampilkan log detail',
                selected: LogService.loggingEnabled.value &&
                    !LogService.errorsOnly.value &&
                    LogService.verboseEnabled.value,
                onTap: () async {
                  await LogService.setLoggingEnabled(true);
                  await LogService.setErrorsOnly(false);
                  await LogService.setVerboseEnabled(true);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logLevelOption({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFAEAEB2),
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color:    Color(0xFF636366),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: Color(0xFF30D158), size: 20),
          ],
        ),
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────────────

  Widget _buildSearch() => Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color:        const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  color: Color(0xFF48484A), size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                    color:      Color(0xFFAEAEB2),
                    fontSize:   13,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText:      'Cari pesan atau kategori…',
                    hintStyle:     TextStyle(
                      color:      Color(0xFF3A3A3C),
                      fontSize:   13,
                      fontFamily: 'monospace',
                    ),
                    border:         InputBorder.none,
                    isDense:        true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(_expanded.clear),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(_expanded.clear);
                  },
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF48484A), size: 15),
                ),
            ],
          ),
        ),
      );

  // ── Filter row ──────────────────────────────────────────────────────────────

  Widget _buildFilterRow(List<String> categories) {
    final totalCount = LogService.logCount.value;

    return Container(
      color: Colors.black,
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _levelChip(null,             'ALL',  totalCount),
          _levelChip(LogLevel.error,   'ERR',  _countLevel(LogLevel.error)),
          _levelChip(LogLevel.warning, 'WRN',  _countLevel(LogLevel.warning)),
          _levelChip(LogLevel.info,    'INF',  _countLevel(LogLevel.info)),
          _levelChip(LogLevel.verbose, 'VRB',  _countLevel(LogLevel.verbose)),
          if (categories.isNotEmpty) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('│',
                    style: TextStyle(
                        color: Color(0xFF2C2C2E),
                        fontFamily: 'monospace')),
              ),
            ),
            ...categories.map(_catChip),
          ],
        ],
      ),
    );
  }

  Widget _levelChip(LogLevel? level, String label, int count) {
    final active = _levelFilter == level;
    final color  = level == null ? Colors.white : _levelColor(level);
    return GestureDetector(
      onTap: () => setState(() {
        _levelFilter = level;
        _expanded.clear();
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color:      active ? color : const Color(0xFF48484A),
                fontSize:   11,
                fontFamily: 'monospace',
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color:      active ? color.withValues(alpha: 0.6) : const Color(0xFF3A3A3C),
                  fontSize:   9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _catChip(String cat) {
    final active = _categoryFilter == cat;
    return GestureDetector(
      onTap: () => setState(() {
        _categoryFilter = active ? null : cat;
        _expanded.clear();
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFAEAEB2).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active
              ? Border.all(
                  color: const Color(0xFFAEAEB2).withValues(alpha: 0.2),
                  width: 0.5)
              : null,
        ),
        child: Text(
          cat,
          style: TextStyle(
            color:      active ? const Color(0xFFAEAEB2) : const Color(0xFF48484A),
            fontSize:   11,
            fontFamily: 'monospace',
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ── Log list ────────────────────────────────────────────────────────────────

  Widget _buildList(List<LogEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal_rounded,
                color: Color(0xFF2C2C2E), size: 36),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty ||
                      _levelFilter != null ||
                      _categoryFilter != null
                  ? 'tidak ada hasil'
                  : 'belum ada log',
              style: const TextStyle(
                color:      Color(0xFF3A3A3C),
                fontSize:   12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller:  _scrollCtrl,
      padding:     const EdgeInsets.only(bottom: 16),
      itemCount:   entries.length,
      itemBuilder: (_, i) => _buildEntry(entries[i], i),
    );
  }

  Widget _buildEntry(LogEntry entry, int i) {
    final hasStack = (entry.stackTrace ?? '').isNotEmpty;
    final expanded = _expanded.contains(i);
    final color    = _levelColor(entry.level);

    return GestureDetector(
      behavior:    HitTestBehavior.opaque,
      onTap:       hasStack ? () => setState(() {
        if (expanded) { _expanded.remove(i); }
        else          { _expanded.add(i); }
      }) : null,
      onLongPress: () {
        HapticFeedback.lightImpact();
        _copyEntry(entry);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Level color bar
                Container(
                  width: 3,
                  color: color.withValues(alpha: 0.5),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: category + level tag + timestamp + chevron
                        Row(
                          children: [
                            Text(
                              entry.category.toUpperCase(),
                              style: TextStyle(
                                color:       color.withValues(alpha: 0.55),
                                fontSize:    9,
                                fontFamily:  'monospace',
                                fontWeight:  FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color:        color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                entry.levelTag,
                                style: TextStyle(
                                  color:      color.withValues(alpha: 0.6),
                                  fontSize:   8,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              entry.formattedTime,
                              style: const TextStyle(
                                color:      Color(0xFF3A3A3C),
                                fontSize:   9.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (hasStack) ...[
                              const SizedBox(width: 4),
                              Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: const Color(0xFF3A3A3C),
                                size:  14,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Row 2: message
                        Text(
                          entry.message,
                          style: TextStyle(
                            color: switch (entry.level) {
                              LogLevel.error   => const Color(0xFFF92D48)
                                  .withValues(alpha: 0.9),
                              LogLevel.warning => const Color(0xFFFF9F0A)
                                  .withValues(alpha: 0.9),
                              LogLevel.verbose => const Color(0xFF48484A),
                              _                => const Color(0xFFAEAEB2),
                            },
                            fontSize:   12,
                            fontFamily: 'monospace',
                            height:     1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Stack trace — expanded
          if (hasStack && expanded)
            Container(
              margin:  const EdgeInsets.fromLTRB(13, 0, 12, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(6),
                border:       Border.all(
                    color: color.withValues(alpha: 0.15), width: 0.5),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  entry.stackTrace!,
                  style: const TextStyle(
                    color:      Color(0xFF636366),
                    fontSize:   9.5,
                    fontFamily: 'monospace',
                    height:     1.65,
                  ),
                ),
              ),
            ),
          Container(height: 0.5, color: const Color(0xFF111111)),
        ],
      ),
    );
  }

  // ── Bottom action bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar(List<LogEntry> entries, double safeBottom) =>
      Container(
        color:   const Color(0xFF0A0A0A),
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + safeBottom),
        child: Row(
          children: [
            _BarBtn(
              icon:    Icons.keyboard_double_arrow_up_rounded,
              label:   'Atas',
              onTap:   _jumpTop,
            ),
            const SizedBox(width: 6),
            _BarBtn(
              icon:    Icons.keyboard_double_arrow_down_rounded,
              label:   'Bawah',
              onTap:   _jumpBottom,
            ),
            const Spacer(),
            _BarBtn(
              icon:    Icons.copy_rounded,
              label:   'Salin semua',
              onTap:   () => _copyAll(entries),
              enabled: entries.isNotEmpty,
            ),
            const SizedBox(width: 6),
            _BarBtn(
              icon:        Icons.delete_outline_rounded,
              label:       'Hapus',
              onTap:       _clearLogs,
              destructive: true,
              enabled:     LogService.logCount.value > 0,
            ),
          ],
        ),
      );
}

// Extracted to part files — see log_page/ directory.
