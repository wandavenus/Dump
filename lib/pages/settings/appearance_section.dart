part of '../settings_page.dart';

// ─── TAMPILAN ─────────────────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('TAMPILAN'),
        const SizedBox(height: 6),
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

class _GlassSubToggle extends StatelessWidget {
  final String label;
  final ValueNotifier<bool> notifier;
  final Future<void> Function(bool) onChanged;

  const _GlassSubToggle({
    required this.label,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, value, __) => Padding(
        padding: const EdgeInsets.only(left: 36, right: 16, top: 10, bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.blur_on, size: 16, color: Color(0xFF8E8E93)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFFF92D48),
            ),
          ],
        ),
      ),
    );
  }
}
