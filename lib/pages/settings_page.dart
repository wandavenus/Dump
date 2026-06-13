import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/services/audio_settings_service.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'settings/settings_widgets.dart';

export 'settings/settings_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _SettingsAppBar(),
            SliverToBoxAdapter(child: _SettingsBody()),
          ],
        ),
      ),
    );
  }
}

// ─── AppBar ────────────────────────────────────────────────────────────────────

class _SettingsAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      pinned: true,
      expandedHeight: 100,
      collapsedHeight: kToolbarHeight,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final expandRatio = ((constraints.maxHeight - kToolbarHeight) /
                  (100 - kToolbarHeight))
              .clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Positioned(
                bottom: 13,
                left: 16,
                child: Opacity(
                  opacity: expandRatio,
                  child: Text(
                    'Pengaturan',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(expandRatio),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0),
                  child: const Center(
                    child: Text(
                      'Pengaturan',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 0.5,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0),
                  child: Container(color: const Color(0xFF38383A)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Body ──────────────────────────────────────────────────────────────────────

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24),
        _AppearanceSection(),
        SizedBox(height: 32),
        _AudioSection(),
        SizedBox(height: 32),
        _SystemSection(),
        SizedBox(height: 32),
        _AboutSection(),
        SizedBox(height: 48),
      ],
    );
  }
}

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
                subtitle: 'Efek blur pada seluruh UI',
                value: isGlass,
                onChanged: ThemeController.setGlassTheme,
              ),
              const SettingsDivider(),
              if (isGlass) ...[
                _GlassSubToggle(
                  label: 'NavBar',
                  notifier: ThemeController.glassNavBar,
                  onChanged: ThemeController.setGlassNavBar,
                ),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                  label: 'AppBar',
                  notifier: ThemeController.glassAppBar,
                  onChanged: ThemeController.setGlassAppBar,
                ),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                  label: 'Mini Player',
                  notifier: ThemeController.glassMiniPlayer,
                  onChanged: ThemeController.setGlassMiniPlayer,
                ),
                const SettingsDivider(indent: 52),
                _GlassSubToggle(
                  label: 'Player Sheet',
                  notifier: ThemeController.glassPlayerSheet,
                  onChanged: ThemeController.setGlassPlayerSheet,
                ),
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
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.only(left: 36, right: 16, top: 10, bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.blur_on, size: 16, color: Color(0xFF8E8E93)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
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

// ─── AUDIO ────────────────────────────────────────────────────────────────────

class _AudioSection extends StatelessWidget {
  const _AudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: AudioSettingsService.gaplessPlayback,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Gapless Playback',
            subtitle: 'Putar tanpa jeda antar lagu',
            value: v,
            onChanged: AudioSettingsService.setGapless,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: AudioSettingsService.audioNormalize,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Audio Normalize',
            subtitle: 'Samakan volume semua lagu',
            value: v,
            onChanged: AudioSettingsService.setNormalize,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: AudioSettingsService.crossfadeDuration,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Crossfade',
            subtitle: v == 0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} detik',
            value: v,
            min: 0,
            max: 12,
            onChanged: AudioSettingsService.setCrossfade,
            divisions: 24,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: AudioSettingsService.pitchShift,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Pitch Shift',
            subtitle: v == 0
                ? 'Normal'
                : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitone',
            value: v,
            min: -6,
            max: 6,
            onChanged: AudioSettingsService.setPitch,
            divisions: 24,
            showReset: v != 0,
            onReset: () => AudioSettingsService.setPitch(0),
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: AudioSettingsService.spatialAudio,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Spatial Audio',
            subtitle: 'Simulasi audio 3D surround',
            value: v,
            onChanged: AudioSettingsService.setSpatial,
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── SISTEM ───────────────────────────────────────────────────────────────────

class _SystemSection extends StatelessWidget {
  const _SystemSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SISTEM'),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, __) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),
        SettingsActionRow(
          title: 'Bersihkan Log',
          trailing: '',
          onTap: LogService.clear,
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _showLogs(BuildContext context) {
    final logs = LogService.getLogs();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Log Aktivitas',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text('Belum ada log',
                          style: TextStyle(color: Color(0xFF8E8E93))))
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final log = logs[logs.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[${log.category}]',
                                style: TextStyle(
                                  color: log.level == LogLevel.error
                                      ? const Color(0xFFF92D48)
                                      : log.level == LogLevel.warning
                                          ? Colors.orange
                                          : const Color(0xFF8E8E93),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  log.message,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── TENTANG ─────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader('TENTANG'),
        SizedBox(height: 6),
        SettingsInfoRow(title: 'Versi', trailing: '1.0.0'),
        SettingsDivider(),
        SettingsInfoRow(title: 'Music Player', trailing: '© 2026'),
        SettingsDivider(),
      ],
    );
  }
}
