part of '../settings_page.dart';

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _DebugState.enabled,
      builder: (_, debug, _) => ValueListenableBuilder<PlaybackEngineType>(
        valueListenable: AudioEngineManager.activeEngineType,
        builder: (_, engine, _) {
          final isMedia3 = engine == PlaybackEngineType.media3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const _AppearanceSection(),
              if (isMedia3) ...[
                const SizedBox(height: 32),
                const _AudioSection(),
              ],
              if (!isMedia3) ...[
                const SizedBox(height: 32),
                const _MediaKitAudioSection(),
              ],
              const SizedBox(height: 32),
              const _PlaybackEngineSection(),
              if (isMedia3) ...[
                const SizedBox(height: 32),
                const _SpatialSection(),
                const SizedBox(height: 32),
                const _EqualizerSection(),
              ],
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
          );
        },
      ),
    );
  }
}

// ─── TAMPILAN ─────────────────────────────────────────────────────────────────
