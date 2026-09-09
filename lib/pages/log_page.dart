import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class LogPage extends StatefulWidget {
  final String? initialCategory;
  const LogPage({super.key, this.initialCategory});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  LogLevel? _levelFilter;
  String? _categoryFilter;
  bool _liveTail = true;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _categoryFilter = widget.initialCategory;
    _liveTail = LogService.liveTailEnabled.value;
    LogService.logCount.addListener(_onNewLog);
    LogService.liveTailEnabled.addListener(_onLiveTailChanged);
  }

  @override
  void dispose() {
    LogService.logCount.removeListener(_onNewLog);
    LogService.liveTailEnabled.removeListener(_onLiveTailChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onLiveTailChanged() {
    if (!mounted) return;
    setState(() => _liveTail = LogService.liveTailEnabled.value);
  }

  void _onNewLog() {
    if (!_liveTail || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleLiveTail() {
    final next = !_liveTail;
    setState(() => _liveTail = next);
    unawaited(LogService.setLiveTailEnabled(next));
  }

  List<LogEntry> _filteredEntries() {
    return LogService.entries.where((e) {
      if (_levelFilter != null && e.level != _levelFilter) return false;
      if (_categoryFilter != null && e.category != _categoryFilter) return false;
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty && !e.toString().toLowerCase().contains(q)) return false;
      return true;
    }).toList(growable: false);
  }

  int _countLevel(LogLevel l) => LogService.entries.where((e) => e.level == l).length;

  Color _levelColor(LogLevel l) => switch (l) {
        LogLevel.error => const Color(0xFFF92D48),
        LogLevel.warning => const Color(0xFFFF9F0A),
        LogLevel.info => const Color(0xFF30D158),
        LogLevel.verbose => AppColors.of(context).tertiaryLabel,
      };

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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearLogs() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.logClearTitle),
        content: Text(context.l10n.logClearMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              LogService.clear();
            },
            child: Text(context.l10n.clear),
          ),
        ],
      ),
    );
  }

  void _setLevel(LogLevel? level) {
    setState(() => _levelFilter = level);
  }

  void _setCategory(String? category) {
    setState(() => _categoryFilter = category);
  }

  void _onSearchChanged(String _) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries();
    final c = AppThemeExtension.of(context);
    return Scaffold(
      appBar: _buildAppBar(c),
      body: Column(
        children: [
          _buildFilters(c),
          Expanded(child: _buildList(entries, c)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppThemeExtension c) {
    return AppBar(
      title: Text(context.l10n.logTitle),
      actions: [
        IconButton(
          tooltip: context.l10n.logCopyAll,
          onPressed: _filteredEntries().isEmpty ? null : () => _copyAll(_filteredEntries()),
          icon: const Icon(Icons.copy_all_rounded),
        ),
        IconButton(
          tooltip: context.l10n.logClear,
          onPressed: LogService.entries.isEmpty ? null : _clearLogs,
          icon: const Icon(Icons.delete_sweep_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: GestureDetector(
              onTap: _toggleLiveTail,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _liveTail ? const Color(0xFF30D158) : c.surface3,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _liveTail ? const Color(0xFF30D158) : c.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(AppThemeExtension c) {
    final categories = LogService.entries.map((e) => e.category).toSet().toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: context.l10n.logSearch,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _filterChip('ALL', _levelFilter == null, () => _setLevel(null), c),
              _filterChip('ERROR', _levelFilter == LogLevel.error, () => _setLevel(LogLevel.error), c),
              _filterChip('WARN', _levelFilter == LogLevel.warning, () => _setLevel(LogLevel.warning), c),
              _filterChip('INFO', _levelFilter == LogLevel.info, () => _setLevel(LogLevel.info), c),
              _filterChip('VERBOSE', _levelFilter == LogLevel.verbose, () => _setLevel(LogLevel.verbose), c),
              if (categories.isNotEmpty) ...[
                const VerticalDivider(width: 16),
                _categoryChip(context.l10n.logCategoryAll, _categoryFilter == null, () => _setCategory(null), c),
                ...categories.map((cat) => _categoryChip(cat, _categoryFilter == cat, () => _setCategory(cat), c)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, AppThemeExtension c) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _categoryChip(String label, bool selected, VoidCallback onTap, AppThemeExtension c) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildList(List<LogEntry> entries, AppThemeExtension c) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, color: c.surface2, size: 36),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty || _levelFilter != null || _categoryFilter != null
                  ? context.l10n.logNoResults
                  : context.l10n.logEmpty,
              style: TextStyle(color: c.surface3, fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final expanded = ValueNotifier(false);
        return _LogEntryTile(
          entry: entry,
          expanded: expanded,
          levelColor: _levelColor(entry.level),
          onCopy: () => _copyEntry(entry),
        );
      },
    );
  }
}

class _LogEntryTile extends StatefulWidget {
  final LogEntry entry;
  final ValueNotifier<bool> expanded;
  final Color levelColor;
  final VoidCallback onCopy;

  const _LogEntryTile({
    required this.entry,
    required this.expanded,
    required this.levelColor,
    required this.onCopy,
  });

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  @override
  void dispose() {
    widget.expanded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.expanded,
      builder: (context, isExpanded, _) {
        return Card(
          margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
          child: InkWell(
            onTap: () => widget.expanded.value = !isExpanded,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.entry.level.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: widget.levelColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.entry.category,
                        style: TextStyle(fontSize: 10, color: AppThemeExtension.of(context).secondaryLabel),
                      ),
                      const Spacer(),
                      Text(
                        _formatTime(widget.entry.timestamp),
                        style: TextStyle(fontSize: 10, color: AppThemeExtension.of(context).tertiaryLabel),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.copy,
                        onPressed: widget.onCopy,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                      ),
                    ],
                  ),
                  Text(
                    widget.entry.message,
                    maxLines: isExpanded ? null : 3,
                    overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  if (isExpanded && widget.entry.stackTrace != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.entry.stackTrace!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
