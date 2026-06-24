part of '../settings_page.dart';

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _DebugState.enabled,
      builder: (_, debug, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const _AppearanceSection(),
          const SizedBox(height: 32),
          const _AudioSection(),
          const SizedBox(height: 32),
          const _SpatialSection(),
          const SizedBox(height: 32),
          const _EqualizerSection(),
          const SizedBox(height: 32),
          const _LyricsSection(),
          const SizedBox(height: 32),
          const _AudioOutputSection(),
          const SizedBox(height: 32),
          const _SystemSection(),
          const SizedBox(height: 32),
          if (debug) ...[
            const _DebugSection(),
            const SizedBox(height: 32),
          ],
          const _AboutSection(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ─── TAMPILAN ─────────────────────────────────────────────────────────────────
