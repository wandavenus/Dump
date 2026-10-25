part of '../settings_page.dart';

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  bool _isLiquidGlassExpanded = ThemeController.glassTheme.value;

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
                      if (v != null) unawaited(ThemeController.setMode(v));
                    },
                    children: {
                      ThemeMode.light: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          l.themeLight,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      ThemeMode.system: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          l.themeAutomatic,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      ThemeMode.dark: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          l.themeDark,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.playerBackgroundTitle,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<PlayerBackgroundStyle>(
                valueListenable: ThemeController.playerBackgroundStyle,
                builder: (context, current, _) {
                  return CupertinoSlidingSegmentedControl<
                    PlayerBackgroundStyle
                  >(
                    groupValue: current,
                    onValueChanged: (value) {
                      if (value != null) {
                        unawaited(
                          ThemeController.setPlayerBackgroundStyle(value),
                        );
                      }
                    },
                    children: {
                      PlayerBackgroundStyle.fluid: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          l.playerBackgroundFluid,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      PlayerBackgroundStyle.artworkBlur: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          l.playerBackgroundArtwork,
                          style: const TextStyle(fontSize: 13),
                        ),
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
          valueListenable: ThemeController.glassTheme,
          builder: (context, isGlass, _) => Column(
            children: [
              Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(
                            () => _isLiquidGlassExpanded = !_isLiquidGlassExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.liquidGlass,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l.liquidGlassSubtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.of(context).secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: isGlass,
                        onChanged: (enabled) {
                          unawaited(ThemeController.setGlassTheme(enabled));
                          if (enabled && !_isLiquidGlassExpanded) {
                            setState(() => _isLiquidGlassExpanded = true);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: _isLiquidGlassExpanded
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: ValueListenableBuilder<NavBarStyle>(
                              valueListenable: ThemeController.navBarStyle,
                              builder: (context, current, _) {
                                return SizedBox(
                                  width: double.infinity,
                                  child: CupertinoSlidingSegmentedControl<NavBarStyle>(
                                    groupValue: current,
                                    onValueChanged: (v) {
                                      if (v != null) {
                                        unawaited(ThemeController.setNavBarStyle(v));
                                      }
                                    },
                                    children: {
                                      NavBarStyle.solid: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          l.navBarStyleSolid,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      NavBarStyle.glass: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          l.navBarStyleGlass,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      NavBarStyle.pill: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          l.navBarStylePill,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    },
                                  ),
                                );
                              },
                            ),
                          ),

                        ],
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
              const SettingsDivider(),
            ],
          ),
        ),
      ],
    );
  }
}
