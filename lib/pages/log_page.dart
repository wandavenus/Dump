import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/theme/app_colors.dart';
import 'package:musicplayer/themes/app_theme_extension.dart';

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
  String? _categoryFilter;
  bool _liveTail = true; // auto-scroll ke entri terbaru

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  // Expanded stack traces, keyed by the LogEntry itself (not a list index) so
  // entries stay expanded across new-log insertions; pruned when the entry is
  // evicted from the ring buffer (L-5 fix).
  final Set<LogEntry> _expanded = {};
  // L-2 fix: log bursts (crossfade timeline, restore, prewarm, scans) fire
  // logCount dozens of times in a row — each one used to trigger a full
  // rebuild + O(n) filter scans. Debounce into a single rebuild so the page
  // stays smooth while a burst is landing.
  Timer? _newLogDebounce;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategory;
    LogService.logCount.addListener(_onNewLog);
  }

  @override
  void dispose() {
    _newLogDebounce?.cancel();
    LogService.logCount.removeListener(_onNewLog);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    _newLogDebounce?.cancel();
    _newLogDebounce = Timer(const Duration(milliseconds: 150), _applyNewLog);
  }

  void _applyNewLog() {
    if (!mounted) return;
    setState(() {
      // L-5 fix: keep user-expanded stack traces; only drop ones whose entry
      // was evicted from the ring buffer (they can no longer be shown anyway).
      _expanded.removeWhere((e) => !LogService.contains(e));
    });
    if (_liveTail && _scrollCtrl.hasClients) {
      unawaited(
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  // ── Data helpers ────────────────────────────────────────────────────────────

  List<LogEntry> get _filtered => LogService.getLogs(
    level: _levelFilter,
    category: _categoryFilter,
    search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
  ).reversed.toList();

  // L-6 fix: per-level chip counts follow the active category/search filter
  // so the badge numbers match the entries actually listed below.
  int _countLevel(LogLevel l) => LogService.countByLevel(
    l,
    category: _categoryFilter,
    search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
  );

  /// Total entries under the active category/search filter (all levels) —
  /// what the "ALL" chip shows.
  int get _filteredTotal => LogService.getLogs(
    category: _categoryFilter,
    search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
  ).length;

  Color _levelColor(LogLevel l) => switch (l) {
    LogLevel.error => const Color(0xFFF92D48),
    LogLevel.warning => const Color(0xFFFF9F0A),
    LogLevel.info => const Color(0xFF30D158),
    LogLevel.verbose => AppColors.of(context).tertiaryLabel,
  };

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _copyAll(List<LogEntry> entries) {
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln(e.toString());
    }
    unawaited(Clipboard.setData(ClipboardData(text: buf.toString())));
    _snack(context.l10n.logCopiedEntries(entries.length));
  }

  void _copyEntry(LogEntry e) {
    unawaited(Clipboard.setData(ClipboardData(text: e.toString())));
    _snack(context.l10n.logCopiedEntry);
  }

  void _snack(String msg) {
    if (!mounted) return;
    final c = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        backgroundColor: c.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _jumpTop() {
    if (!_scrollCtrl.hasClients) return;
    unawaited(
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _jumpBottom() {
    if (!_scrollCtrl.hasClients) return;
    unawaited(
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _clearLogs() {
    unawaited(
      showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dc = AppColors.of(ctx);
          return AlertDialog(
            backgroundColor: dc.surface,
            title: Text(
              ctx.l10n.clearLogsConfirm,
              style: TextStyle(color: dc.primaryLabel, fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  ctx.l10n.cancel,
                  style: TextStyle(color: dc.tertiaryLabel),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  ctx.l10n.delete,
                  style: TextStyle(color: Color(0xFFF92D48)),
                ),
              ),
            ],
          );
        },
      ).then((confirmed) {
        if (!mounted) return;
        if (confirmed == true) {
          LogService.clear();
          setState(_expanded.clear);
        }
      }),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final entries = _filtered;
    final categories = LogService.getCategories();
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(entries, c),
      body: Column(
        children: [
          _LogFilterBar(
            levelFilter: _levelFilter,
            categoryFilter: _categoryFilter,
            categories: categories,
            totalCount: _filteredTotal,
            countLevel: _countLevel,
            levelColor: _levelColor,
            searchController: _searchCtrl,
            onLevelChanged: (l) => setState(() {
              _levelFilter = l;
              _expanded.clear();
            }),
            onCategoryChanged: (cat) => setState(() {
              _categoryFilter = cat;
              _expanded.clear();
            }),
            onSearchChanged: () => setState(_expanded.clear),
          ),
          Expanded(child: _buildList(entries, c)),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(entries, safeBottom, c),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    List<LogEntry> entries,
    AppThemeExtension c,
  ) {
    final errCount = _countLevel(LogLevel.error);
    final warnCount = _countLevel(LogLevel.warning);

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: c.primaryLabel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
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
          Text(
            context.l10n.logTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.logEntryCount(entries.length),
            style: TextStyle(
              color: c.quaternaryLabel,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 10),
          if (errCount > 0)
            _AppBarBadge(count: errCount, color: const Color(0xFFF92D48)),
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
                    : c.dimLabel.withValues(alpha: 0.2),
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
                        : c.quaternaryLabel,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.liveLabel,
                    style: TextStyle(
                      color: _liveTail
                          ? const Color(0xFF30D158)
                          : c.quaternaryLabel,
                      fontSize: 10,
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

  // ── Log list ────────────────────────────────────────────────────────────────

  Widget _buildList(List<LogEntry> entries, AppThemeExtension c) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, color: c.surface2, size: 36),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty ||
                      _levelFilter != null ||
                      _categoryFilter != null
                  ? context.l10n.logNoResults
                  : context.l10n.logEmpty,
              style: TextStyle(
                color: c.surface3,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final hasStack = (entry.stackTrace ?? '').isNotEmpty;
        return _LogEntryTile(
          entry: entry,
          expanded: _expanded.contains(entry),
          levelColor: _levelColor,
          onToggleExpand: hasStack
              ? () => setState(() {
                  if (!_expanded.remove(entry)) {
                    _expanded.add(entry);
                  }
                })
              : null,
          onCopy: () => _copyEntry(entry),
        );
      },
    );
  }

  // ── Bottom action bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar(
    List<LogEntry> entries,
    double safeBottom,
    AppThemeExtension c,
  ) => Container(
    color: c.codeBackground,
    padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + safeBottom),
    child: Row(
      children: [
        _BarBtn(
          icon: Icons.keyboard_double_arrow_up_rounded,
          label: context.l10n.logScrollTop,
          onTap: _jumpTop,
        ),
        const SizedBox(width: 6),
        _BarBtn(
          icon: Icons.keyboard_double_arrow_down_rounded,
          label: context.l10n.logScrollBottom,
          onTap: _jumpBottom,
        ),
        const Spacer(),
        _BarBtn(
          icon: Icons.copy_rounded,
          label: context.l10n.logCopyAll,
          onTap: () => _copyAll(entries),
          enabled: entries.isNotEmpty,
        ),
        const SizedBox(width: 6),
        _BarBtn(
          icon: Icons.delete_outline_rounded,
          label: context.l10n.delete,
          onTap: _clearLogs,
          destructive: true,
          enabled: LogService.logCount.value > 0,
        ),
      ],
    ),
  );
}
