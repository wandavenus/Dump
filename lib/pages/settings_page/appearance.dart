part of '../settings_page.dart';

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('TAMPILAN'),
        const SizedBox(height: 6),
        // ── Tema ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.brightness_6_outlined, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Tema', style: TextStyle(fontSize: 16)),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeController.mode,
                builder: (context, current, _) {
                  return CupertinoSlidingSegmentedControl<ThemeMode>(
                    groupValue: current,
                    onValueChanged: (v) {
                      if (v != null) ThemeController.setMode(v);
                    },
                    children: const {
                      ThemeMode.light:  Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Terang', style: TextStyle(fontSize: 13)),
                      ),
                      ThemeMode.system: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Otomatis', style: TextStyle(fontSize: 13)),
                      ),
                      ThemeMode.dark:   Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Gelap', style: TextStyle(fontSize: 13)),
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
            title: 'Tampilkan Up Next',
            subtitle: 'Kartu lagu berikutnya di player',
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
                title: 'Liquid Glass',
                subtitle: 'Efek blur transparan pada seluruh UI',
                value: isGlass,
                onChanged: ThemeController.setGlassTheme,
              ),
              const SettingsDivider(),
              if (isGlass) ...[
                _GlassSubToggle(label: 'NavBar',        notifier: ThemeController.glassNavBar,      onChanged: ThemeController.setGlassNavBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'AppBar',        notifier: ThemeController.glassAppBar,      onChanged: ThemeController.setGlassAppBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Mini Player',   notifier: ThemeController.glassMiniPlayer,  onChanged: ThemeController.setGlassMiniPlayer),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Player Sheet',  notifier: ThemeController.glassPlayerSheet, onChanged: ThemeController.setGlassPlayerSheet),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Album Card',    notifier: ThemeController.glassAlbumCard,   onChanged: ThemeController.setGlassAlbumCard),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Artist Card',   notifier: ThemeController.glassArtistCard,  onChanged: ThemeController.setGlassArtistCard),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Library Bar',   notifier: ThemeController.glassLibraryBar,  onChanged: ThemeController.setGlassLibraryBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Search Bar',    notifier: ThemeController.glassSearchBar,   onChanged: ThemeController.setGlassSearchBar),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(label: 'Halaman Pengaturan', notifier: ThemeController.glassSettings, onChanged: ThemeController.setGlassSettings),
                const SettingsDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
