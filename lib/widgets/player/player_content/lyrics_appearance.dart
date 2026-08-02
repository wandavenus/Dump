part of '../player_content.dart';

// ─── Appearance button (circle icon, top-right in lyrics mode) ───────────────

class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromARGB(90, 100, 100, 100),
        ),
        child: const Icon(
          CupertinoIcons.ellipsis_vertical,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  void _show(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: AnimationStyle.noAnimation,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const _LyricsAppearanceOverlay(),
      ),
    );
  }
}

// ─── Appearance settings sheet ────────────────────────────────────────────────

class _LyricsAppearanceOverlay extends StatelessWidget {
  const _LyricsAppearanceOverlay();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.dragHandle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.lyricsAppearance,
                  style: TextStyle(
                    color: c.primaryLabel,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _buildLabel(c, context.l10n.textSizeLabel),
                const SizedBox(height: 8),
                const _FontSizePicker(),
                const SizedBox(height: 16),
                _buildLabel(c, context.l10n.textAlignLabel),
                const SizedBox(height: 8),
                const _AlignPicker(),
                const SizedBox(height: 16),
                _buildLabel(c, context.l10n.activeColorLabel),
                const SizedBox(height: 8),
                const _ColorPicker(),
                const SizedBox(height: 12),
                _ToggleRow(
                  label: context.l10n.karaokeHighlight,
                  subtitle: context.l10n.karaokeHighlightSubtitle,
                  notifier: LyricsSettings.karaokeMode,
                  onChanged: LyricsSettings.setKaraokeMode,
                ),
                const SizedBox(height: 4),
                _ToggleRow(
                  label: context.l10n.showLyricsSource,
                  notifier: LyricsSettings.showSource,
                  onChanged: LyricsSettings.setShowSource,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildLabel(AppThemeExtension c, String text) => Text(
    text,
    style: TextStyle(
      color: c.secondaryLabel,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );
}

// ─── Reusable toggle row ──────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final ValueNotifier<bool> notifier;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, v, _) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: c.primaryLabel, fontSize: 15),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(color: c.secondaryLabel, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: v,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFFF92D48),
          ),
        ],
      ),
    );
  }
}
