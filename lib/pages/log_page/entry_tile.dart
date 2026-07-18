part of '../log_page.dart';

/// Single log entry tile.
///
/// Renders the colored level bar, category/level/timestamp header row,
/// message text, and an optional expandable stack trace panel.
/// All state lives in [_LogPageState]; this widget is purely presentational.
class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({
    required this.entry,
    required this.expanded,
    required this.levelColor,
    required this.onToggleExpand,
    required this.onCopy,
  });

  final LogEntry entry;
  final bool expanded;
  final Color Function(LogLevel) levelColor;
  final VoidCallback? onToggleExpand; // null when no stack trace
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final hasStack = (entry.stackTrace ?? '').isNotEmpty;
    final color    = levelColor(entry.level);

    return GestureDetector(
      behavior:    HitTestBehavior.opaque,
      onTap:       hasStack ? onToggleExpand : null,
      onLongPress: () {
        HapticFeedback.lightImpact();
        onCopy();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Level color bar
                Container(width: 3, color: color.withValues(alpha: 0.5)),
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
                                color:         color.withValues(alpha: 0.55),
                                fontSize:      9,
                                fontFamily:    'monospace',
                                fontWeight:    FontWeight.w700,
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
          // Stack trace panel — shown when expanded
          if (hasStack && expanded)
            Container(
              margin:  const EdgeInsets.fromLTRB(13, 0, 12, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
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
}
