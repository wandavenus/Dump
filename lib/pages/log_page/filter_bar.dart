part of '../log_page.dart';

/// Search field + horizontal filter chips row.
///
/// Composed of two sections rendered top-to-bottom:
///  1. Search [TextField] bound to [searchController]
///  2. Level chips (ALL / ERR / WRN / INF / VRB) + category chips
///
/// All state lives in [_LogPageState]; this widget is purely presentational.
class _LogFilterBar extends StatelessWidget {
  const _LogFilterBar({
    required this.levelFilter,
    required this.categoryFilter,
    required this.categories,
    required this.totalCount,
    required this.countLevel,
    required this.levelColor,
    required this.searchController,
    required this.onLevelChanged,
    required this.onCategoryChanged,
    required this.onSearchChanged,
  });

  final LogLevel?    levelFilter;
  final String?      categoryFilter;
  final List<String> categories;
  final int          totalCount;
  final int   Function(LogLevel) countLevel;
  final Color Function(LogLevel) levelColor;
  final TextEditingController    searchController;
  final ValueChanged<LogLevel?>  onLevelChanged;
  final ValueChanged<String?>    onCategoryChanged;
  /// Called on every text change AND when the clear button is tapped.
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final c         = AppColors.of(context);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSearch(context, c, scaffoldBg),
        _buildFilterRow(context, c, scaffoldBg),
        Divider(height: 1, thickness: 0.5, color: c.surface),
      ],
    );
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Widget _buildSearch(BuildContext context, AppThemeExtension c, Color scaffoldBg) =>
      Container(
        color: scaffoldBg,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color:        c.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  color: c.quaternaryLabel, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: TextStyle(
                    color:      c.primaryLabel,
                    fontSize:   13,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText:  'Cari pesan atau kategori…',
                    hintStyle: TextStyle(
                      color:      c.dimLabel,
                      fontSize:   13,
                      fontFamily: 'monospace',
                    ),
                    border:         InputBorder.none,
                    isDense:        true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => onSearchChanged(),
                ),
              ),
              if (searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    searchController.clear();
                    onSearchChanged(); // controller.clear() doesn't fire onChanged
                  },
                  child: Icon(Icons.close_rounded,
                      color: c.quaternaryLabel, size: 15),
                ),
            ],
          ),
        ),
      );

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilterRow(BuildContext context, AppThemeExtension c, Color scaffoldBg) {
    return Container(
      color:  scaffoldBg,
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _levelChip(null,             'ALL', totalCount, c),
          _levelChip(LogLevel.error,   'ERR', countLevel(LogLevel.error), c),
          _levelChip(LogLevel.warning, 'WRN', countLevel(LogLevel.warning), c),
          _levelChip(LogLevel.info,    'INF', countLevel(LogLevel.info), c),
          _levelChip(LogLevel.verbose, 'VRB', countLevel(LogLevel.verbose), c),
          if (categories.isNotEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('│',
                    style: TextStyle(
                        color: c.surface2, fontFamily: 'monospace')),
              ),
            ),
            ...categories.map((cat) => _catChip(cat, c)),
          ],
        ],
      ),
    );
  }

  Widget _levelChip(LogLevel? level, String label, int count, AppThemeExtension c) {
    final active = levelFilter == level;
    final color  = level == null ? c.primaryLabel : levelColor(level);
    return GestureDetector(
      onTap: () => onLevelChanged(level),
      child: Container(
        margin:  const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color:      active ? color : c.quaternaryLabel,
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
                  color: active
                      ? color.withValues(alpha: 0.6)
                      : c.dimLabel,
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

  Widget _catChip(String cat, AppThemeExtension c) {
    final active = categoryFilter == cat;
    return GestureDetector(
      onTap: () => onCategoryChanged(active ? null : cat),
      child: Container(
        margin:  const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? c.secondaryLabel.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: active
              ? Border.all(
                  color: c.secondaryLabel.withValues(alpha: 0.2),
                  width: 0.5)
              : null,
        ),
        child: Text(
          cat,
          style: TextStyle(
            color:      active ? c.secondaryLabel : c.quaternaryLabel,
            fontSize:   11,
            fontFamily: 'monospace',
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
