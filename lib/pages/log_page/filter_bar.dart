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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSearch(),
        _buildFilterRow(),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFF1C1C1E)),
      ],
    );
  }

  // ── Search ─────────────────────────────────────────────────────────────────

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
                  controller: searchController,
                  style: const TextStyle(
                    color:      Color(0xFFAEAEB2),
                    fontSize:   13,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText:  'Cari pesan atau kategori…',
                    hintStyle: TextStyle(
                      color:      Color(0xFF3A3A3C),
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
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF48484A), size: 15),
                ),
            ],
          ),
        ),
      );

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return Container(
      color:  Colors.black,
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _levelChip(null,             'ALL', totalCount),
          _levelChip(LogLevel.error,   'ERR', countLevel(LogLevel.error)),
          _levelChip(LogLevel.warning, 'WRN', countLevel(LogLevel.warning)),
          _levelChip(LogLevel.info,    'INF', countLevel(LogLevel.info)),
          _levelChip(LogLevel.verbose, 'VRB', countLevel(LogLevel.verbose)),
          if (categories.isNotEmpty) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('│',
                    style: TextStyle(
                        color: Color(0xFF2C2C2E), fontFamily: 'monospace')),
              ),
            ),
            ...categories.map(_catChip),
          ],
        ],
      ),
    );
  }

  Widget _levelChip(LogLevel? level, String label, int count) {
    final active = levelFilter == level;
    final color  = level == null ? Colors.white : levelColor(level);
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
                  color: active
                      ? color.withValues(alpha: 0.6)
                      : const Color(0xFF3A3A3C),
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
    final active = categoryFilter == cat;
    return GestureDetector(
      onTap: () => onCategoryChanged(active ? null : cat),
      child: Container(
        margin:  const EdgeInsets.only(right: 6),
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
}
