part of '../settings_page.dart';

class _BitPerfectSection extends StatelessWidget {
  const _BitPerfectSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ValueListenableBuilder<bool>(
      valueListenable: AudioEffectsService.bitPerfectMode,
      builder: (context, enabled, _) {
        final c = AppColors.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionHeader(l.sectionBitPerfect),
            const SizedBox(height: 6),
            SettingsToggleRow(
              title: l.bitPerfectMode,
              subtitle: enabled
                  ? l.bitPerfectActiveSubtitle
                  : l.bitPerfectInactiveSubtitle,
              value: enabled,
              onChanged: (v) => _confirmAndToggle(context, v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Text(
                l.bitPerfectDescription,
                style: TextStyle(color: c.tertiaryLabel, fontSize: 12),
              ),
            ),
            const SettingsDivider(),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndToggle(BuildContext context, bool value) async {
    if (!value) {
      await AudioEffectsService.setBitPerfectMode(false);
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BitPerfectConfirmSheet(),
    );
    if (confirmed == true) {
      await AudioEffectsService.setBitPerfectMode(true);
    }
  }
}

class _BitPerfectConfirmSheet extends StatelessWidget {
  const _BitPerfectConfirmSheet();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.bitPerfectConfirmTitle,
                  style: TextStyle(
                    color: c.primaryLabel,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.bitPerfectConfirmBody,
                  style: TextStyle(color: c.secondaryLabel, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l.cancel,
                          style: TextStyle(color: c.primaryLabel)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: const Color(0xFFF92D48),
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l.activate,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
