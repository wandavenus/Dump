import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicplayer/services/log_service.dart';

part 'log_page/bar_btn.dart';
part 'log_page/app_bar_badge.dart';
part 'log_page/entry_tile.dart';
part 'log_page/filter_bar.dart';
part 'log_page/log_level_selector.dart';

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
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
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
    for (final e in entries) { buf.writeln(e.toString()); }
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
    _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
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
          _LogFilterBar(
            levelFilter:      _levelFilter,
            categoryFilter:   _categoryFilter,
            categories:       categories,
            totalCount:       LogService.logCount.value,
            countLevel:       _countLevel,
            levelColor:       _levelColor,
            searchController: _searchCtrl,
            onLevelChanged:   (l) => setState(() {
              _levelFilter = l;
              _expanded.clear();
            }),
            onCategoryChanged: (c) => setState(() {
              _categoryFilter = c;
              _expanded.clear();
            }),
            onSearchChanged: () => setState(_expanded.clear),
          ),
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
      elevation:    0,
      titleSpacing: 0,
      leading: CupertinoButton(
        padding: const EdgeInsets.only(left: 8),
        onPressed: () => Navigator.of(context).pop(),
        child: const Icon(
          CupertinoIcons.arrow_left,
          color: Color(0xFFF92D48),
          size: 28,
        ),
      ),
      title: Row(
        children: [
          const Text('Log',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
          const SizedBox(width: 8),
          Text('${entries.length}',
              style: const TextStyle(
                  color: Color(0xFF48484A), fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(width: 10),
          if (errCount > 0)
            _AppBarBadge(count: errCount,  color: const Color(0xFFF92D48)),
          if (errCount > 0 && warnCount > 0) const SizedBox(width: 5),
          if (warnCount > 0)
            _AppBarBadge(count: warnCount, color: const Color(0xFFFF9F0A)),
        ],
      ),
      actions: [
        const _LogLevelSelector(),
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
                  Icon(Icons.fiber_manual_record,
                      size: 7,
                      color: _liveTail
                          ? const Color(0xFF30D158)
                          : const Color(0xFF48484A)),
                  const SizedBox(width: 4),
                  Text('LIVE',
                      style: TextStyle(
                        color: _liveTail
                            ? const Color(0xFF30D158)
                            : const Color(0xFF48484A),
                        fontSize:   10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
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
      itemBuilder: (_, i) {
        final entry    = entries[i];
        final hasStack = (entry.stackTrace ?? '').isNotEmpty;
        return _LogEntryTile(
          entry:    entry,
          expanded: _expanded.contains(i),
          levelColor: _levelColor,
          onToggleExpand: hasStack
              ? () => setState(() {
                    if (_expanded.contains(i)) {
                      _expanded.remove(i);
                    } else {
                      _expanded.add(i);
                    }
                  })
              : null,
          onCopy: () => _copyEntry(entry),
        );
      },
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
              icon:  Icons.keyboard_double_arrow_up_rounded,
              label: 'Atas',
              onTap: _jumpTop,
            ),
            const SizedBox(width: 6),
            _BarBtn(
              icon:  Icons.keyboard_double_arrow_down_rounded,
              label: 'Bawah',
              onTap: _jumpBottom,
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
