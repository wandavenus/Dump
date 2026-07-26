part of '../settings_page.dart';

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionAppearance),
        const SizedBox(height: 6),
        // ── Tema ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.themeTitle, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeController.mode,
                builder: (context, current, _) {
                  return CupertinoSlidingSegmentedControl<ThemeMode>(
                    groupValue: current,
                    onValueChanged: (v) {
                      if (v != null) ThemeController.setMode(v);
                    },
                    children: {
                      ThemeMode.light: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(l.themeLight,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      ThemeMode.system: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(l.themeAutomatic,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      ThemeMode.dark: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(l.themeDark,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: UpNextSettings.showUpNextCard,
          builder: (_, show, _) => SettingsToggleRow(
            title: l.showUpNext,
            subtitle: l.showUpNextSubtitle,
            value: show,
            onChanged: UpNextSettings.setShowUpNextCard,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlass, _) => Column(
            children: [
              SettingsToggleRow(
                title: l.liquidGlass,
                subtitle: l.liquidGlassSubtitle,
                value: isGlass,
                onChanged: ThemeController.setGlassTheme,
              ),
              const SettingsDivider(),
              if (isGlass) ...[
                _GlassSubToggle(
                    label: 'NavBar',
                    notifier: ThemeController.glassNavBar,
                    onChanged: ThemeController.setGlassNavBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                    label: 'AppBar',
                    notifier: ThemeController.glassAppBar,
                    onChanged: ThemeController.setGlassAppBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                    label: 'Mini Player',
                    notifier: ThemeController.glassMiniPlayer,
                    onChanged: ThemeController.setGlassMiniPlayer),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                    label: 'Player Sheet',
                    notifier: ThemeController.glassPlayerSheet,
                    onChanged: ThemeController.setGlassPlayerSheet),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                    label: 'Album Card',
                    notifier: ThemeController.glassAlbumCard,
                    onChanged: ThemeController.setGlassAlbumCard),
                const SettingsDivider(indent: 52),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
