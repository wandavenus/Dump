import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/models/lyrics_settings.dart';
import 'package:musicplayer/services/audio/audio_effects_service.dart';
import 'package:musicplayer/services/audio/audio_engine.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/services/sleep_timer_service.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'settings/settings_widgets.dart';
import 'settings/equalizer_page.dart';
import 'settings/sleep_timer_page.dart';

export 'settings/settings_widgets.dart';

// ─── Debug mode state (global, in-memory only) ────────────────────────────────
class _DebugState {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<int>  notifIcon = ValueNotifier(0);

  static const List<({String label, String icon})> notifIcons = [
    (label: 'Default',     icon: 'ic_notification'),
    (label: 'Music Note',  icon: 'ic_notif_note'),
    (label: 'Headphones',  icon: 'ic_notif_headphones'),
    (label: 'Waveform',    icon: 'ic_notif_wave'),
    (label: 'Disk',        icon: 'ic_notif_disk'),
  ];
}

// ─── Page ─────────────────────────────────────────────────────────────────────

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

// ─── AppBar ───────────────────────────────────────────────────────────────────

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

// ─── Body ─────────────────────────────────────────────────────────────────────

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _DebugState.enabled,
      builder: (_, debug, __) => Column(
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
          const _SleepTimerSection(),
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

        // Gapless
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.gaplessPlayback,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Gapless Playback',
            subtitle: 'Putar tanpa jeda antar lagu',
            value: v,
            onChanged: AudioEffectsService.setGapless,
          ),
        ),
        const SettingsDivider(),

        // Normalize
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.audioNormalize,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Audio Normalize',
            subtitle: 'Samakan volume semua lagu (AndroidLoudnessEnhancer)',
            value: v,
            onChanged: AudioEffectsService.setNormalize,
          ),
        ),
        const SettingsDivider(),

        // Crossfade
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.crossfadeDuration,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Crossfade',
            subtitle: v == 0 ? 'Nonaktif' : '${v.toStringAsFixed(1)} detik',
            value: v,
            min: 0,
            max: 12,
            onChanged: AudioEffectsService.setCrossfade,
            divisions: 24,
          ),
        ),
        const SettingsDivider(),

        // Playback Speed
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            onChanged: AudioEffectsService.setSpeed,
            divisions: 22,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
          ),
        ),
        const SettingsDivider(),

        // Pitch Shift
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Pitch Shift',
            subtitle: v == 0
                ? 'Normal'
                : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitone',
            value: v,
            min: -6,
            max: 6,
            onChanged: AudioEffectsService.setPitch,
            divisions: 24,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setPitch(0),
          ),
        ),
        const SettingsDivider(),

        // Bass Boost
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.bassBoost,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Bass Boost',
            subtitle: v == 0
                ? 'Nonaktif'
                : AudioEngine.bassBoostSupported
                    ? '${(v / 10).round()}%'
                    : 'Tidak didukung perangkat ini',
            value: v.toDouble(),
            min: 0,
            max: 1000,
            onChanged: (val) => AudioEffectsService.setBassBoost(val.round()),
            divisions: 20,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setBassBoost(0),
          ),
        ),
        const SettingsDivider(),

        // Reverb
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.reverbPreset,
          builder: (_, v, __) => _ReverbRow(preset: v),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

class _ReverbRow extends StatelessWidget {
  final int preset;
  const _ReverbRow({required this.preset});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showReverbPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reverb',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    AudioEngine.reverbSupported
                        ? AudioEffectsService.reverbPresetNames[preset]
                        : 'Tidak didukung perangkat ini',
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showReverbPicker(BuildContext context) {
    if (!AudioEngine.reverbSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reverb tidak didukung di perangkat ini'),
        backgroundColor: Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Reverb'),
        actions: List.generate(
          AudioEffectsService.reverbPresetNames.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == preset,
            onPressed: () {
              AudioEffectsService.setReverb(i);
              Navigator.of(context).pop();
            },
            child: Text(AudioEffectsService.reverbPresetNames[i]),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

// ─── SPATIAL AUDIO ────────────────────────────────────────────────────────────

class _SpatialSection extends StatelessWidget {
  const _SpatialSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SPATIAL AUDIO'),
        const SizedBox(height: 6),

        // Toggle
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.spatialAudio,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Spatial Audio',
            subtitle: AudioEngine.virtualizerSupported
                ? 'Virtualizer 3D surround (Android AudioEffect)'
                : 'Tidak didukung perangkat ini',
            value: v,
            onChanged: AudioEffectsService.setSpatial,
          ),
        ),
        const SettingsDivider(),

        // Strength slider
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.spatialAudio,
          builder: (_, enabled, __) =>
              ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.spatialStrength,
            builder: (_, strength, __) => SettingsSliderRow(
              title: 'Kekuatan Spatial',
              subtitle: enabled
                  ? '${(strength / 10).round()}%'
                  : 'Aktifkan Spatial Audio terlebih dahulu',
              value: strength.toDouble(),
              min: 0,
              max: 1000,
              onChanged: enabled
                  ? (v) => AudioEffectsService.setSpatialStrength(v.round())
                  : (_) async {},
              divisions: 20,
              showReset: enabled && strength != 1000,
              onReset: () => AudioEffectsService.setSpatialStrength(1000),
            ),
          ),
        ),
        const SettingsDivider(),

        // Info
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Spatial Audio menggunakan Android Virtualizer. '
            'Efek tergantung hardware — MIUI 12 mungkin membatasi akses AudioEffect.',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ─── EQUALIZER ────────────────────────────────────────────────────────────────

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('EQUALIZER'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: AudioEffectsService.equalizerEnabled,
          builder: (_, enabled, __) => SettingsToggleRow(
            title: 'Equalizer',
            subtitle: 'Aktifkan preset ruangan',
            value: enabled,
            onChanged: AudioEffectsService.setEqualizerEnabled,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.roomPreset,
          builder: (_, idx, __) => SettingsActionRow(
            title: 'Preset Ruangan',
            trailing: AudioEffectsService.roomPresets[idx]['name'] as String,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => const EqualizerPage(),
              ),
            ),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── SLEEP TIMER ─────────────────────────────────────────────────────────────

class _SleepTimerSection extends StatelessWidget {
  const _SleepTimerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('SLEEP TIMER'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: SleepTimerService.isActive,
          builder: (_, active, __) => ValueListenableBuilder<Duration?>(
            valueListenable: SleepTimerService.remaining,
            builder: (_, remaining, __) {
              String subtitle;
              if (!active) {
                subtitle = 'Nonaktif';
              } else if (remaining == null) {
                subtitle = 'Berhenti setelah lagu ini';
              } else {
                final m = remaining.inMinutes;
                final s = remaining.inSeconds % 60;
                subtitle = 'Sisa ${m}m ${s}s';
              }
              return SettingsActionRow(
                title: 'Sleep Timer',
                trailing: subtitle,
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const SleepTimerPage(),
                  ),
                ),
              );
            },
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── LIRIK ────────────────────────────────────────────────────────────────────

class _LyricsSection extends StatelessWidget {
  const _LyricsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('LIRIK'),
        const SizedBox(height: 6),

        // Jalur folder .lrc
        _LyricsPathRow(),
        const SettingsDivider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            'Sumber lirik: tag file (MP3/M4A/FLAC/OGG) → folder .lrc → internet.',
            style: TextStyle(color: Color(0xFF636366), fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),

        // ── Pengaturan tampilan lirik ──────────────────────────────────────
        const SettingsSectionHeader('TAMPILAN LIRIK'),
        const SizedBox(height: 6),
        _LyricsAppearanceRows(),
      ],
    );
  }
}

class _LyricsPathRow extends StatefulWidget {
  @override
  State<_LyricsPathRow> createState() => _LyricsPathRowState();
}

class _LyricsPathRowState extends State<_LyricsPathRow> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AudioEffectsService.lyricsPath,
      builder: (_, path, __) => InkWell(
        onTap: () => _showPathDialog(context, path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.lyrics, color: Color(0xFF8E8E93), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jalur Lirik',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      path.isEmpty ? 'Belum ditentukan' : path,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (path.isNotEmpty)
                GestureDetector(
                  onTap: () => AudioEffectsService.setLyricsPath(''),
                  child: const Icon(Icons.clear,
                      color: Color(0xFF8E8E93), size: 18),
                )
              else
                const Icon(Icons.chevron_right,
                    color: Color(0xFF48484A), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showPathDialog(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Jalur Folder Lirik'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '/sdcard/Music/Lyrics',
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const BoxDecoration(color: Color(0xFF2C2C2E)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              AudioEffectsService.setLyricsPath(controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

// ─── TAMPILAN LIRIK (rows dalam settings page) ────────────────────────────────

class _LyricsAppearanceRows extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.fontSize,
          builder: (_, fs, __) {
            final label = fs <= 14 ? 'Kecil (S)' : fs <= 18 ? 'Sedang (M)' : fs <= 22 ? 'Besar (L)' : 'Sangat Besar (XL)';
            return SettingsActionRow(
              title: 'Ukuran Teks Lirik',
              trailing: label,
              onTap: () => _pickFontSize(context, fs),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.textAlign,
          builder: (_, align, __) {
            final label = align == 'center' ? 'Tengah' : align == 'right' ? 'Kanan' : 'Kiri';
            return SettingsActionRow(
              title: 'Rata Teks',
              trailing: label,
              onTap: () => _pickAlign(context, align),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, c, __) {
            final label = c == 'accent' ? 'Merah' : c == 'yellow' ? 'Kuning' : 'Putih';
            return SettingsActionRow(
              title: 'Warna Teks Aktif',
              trailing: label,
              onTap: () => _pickColor(context, c),
            );
          },
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.bgDim,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Kegelapan Latar',
            subtitle: '${(v * 100).round()}%',
            value: v,
            min: 0.2,
            max: 0.95,
            divisions: 15,
            onChanged: LyricsSettings.setBgDim,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.blurStrength,
          builder: (_, v, __) => SettingsSliderRow(
            title: 'Blur Latar',
            subtitle: v == 0 ? 'Nonaktif' : '${v.round()}',
            value: v,
            min: 0,
            max: 50,
            divisions: 10,
            onChanged: LyricsSettings.setBlurStrength,
          ),
        ),
        const SettingsDivider(),
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, v, __) => SettingsToggleRow(
            title: 'Tampilkan Sumber Lirik',
            subtitle: 'Label "Dari internet / Dari file" di halaman lirik',
            value: v,
            onChanged: LyricsSettings.setShowSource,
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }

  void _pickFontSize(BuildContext ctx, double cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Ukuran Teks Lirik'),
        actions: [
          for (final s in [
            (label: 'Kecil (S)', value: 14.0),
            (label: 'Sedang (M)', value: 18.0),
            (label: 'Besar (L)', value: 22.0),
            (label: 'Sangat Besar (XL)', value: 26.0),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: cur == s.value,
              onPressed: () { LyricsSettings.setFontSize(s.value); Navigator.pop(ctx); },
              child: Text(s.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }

  void _pickAlign(BuildContext ctx, String cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Rata Teks Lirik'),
        actions: [
          for (final o in [
            (label: 'Kiri', value: 'left'),
            (label: 'Tengah', value: 'center'),
            (label: 'Kanan', value: 'right'),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: cur == o.value,
              onPressed: () { LyricsSettings.setTextAlign(o.value); Navigator.pop(ctx); },
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }

  void _pickColor(BuildContext ctx, String cur) {
    showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Warna Teks Aktif'),
        actions: [
          for (final o in [
            (label: 'Putih', value: 'white'),
            (label: 'Merah', value: 'accent'),
            (label: 'Kuning', value: 'yellow'),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: cur == o.value,
              onPressed: () { LyricsSettings.setActiveColor(o.value); Navigator.pop(ctx); },
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

// ─── AUDIO OUTPUT ─────────────────────────────────────────────────────────────

class _AudioOutputSection extends StatelessWidget {
  const _AudioOutputSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('JALUR AUDIO'),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: AudioEffectsService.audioOutputMode,
          builder: (_, mode, __) => _AudioOutputRow(mode: mode),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.audioOutputMode,
            builder: (_, mode, __) => Text(
              AudioEffectsService.audioOutputDesc[mode.clamp(0, 2)],
              style: const TextStyle(color: Color(0xFF636366), fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioOutputRow extends StatelessWidget {
  final int mode;
  const _AudioOutputRow({required this.mode});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.settings_input_component,
                color: Color(0xFF8E8E93), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Output Audio',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    AudioEffectsService.audioOutputNames[mode.clamp(0, 2)],
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Jalur Audio Output'),
        message: const Text(
            'AAudio direkomendasikan untuk Android 8+.\n'
            'Hi-Res Audio mengaktifkan DAC hardware (perlu headset hi-res).'),
        actions: List.generate(
          AudioEffectsService.audioOutputNames.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == mode,
            onPressed: () {
              AudioEffectsService.setAudioOutputMode(i);
              Navigator.of(context).pop();
              if (i == 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hi-Res: Pastikan headset hi-res terhubung. '
                        'Di MIUI: Pengaturan → Suara → HiFi Audio.'),
                    backgroundColor: Color(0xFF1C1C1E),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            },
            child: Text(AudioEffectsService.audioOutputNames[i]),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
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

        // Logging toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, enabled, __) => SettingsToggleRow(
            title: 'Logging Aktif',
            subtitle: 'Catat aktivitas & error app',
            value: enabled,
            onChanged: LogService.setLoggingEnabled,
          ),
        ),
        const SettingsDivider(),

        // Errors only toggle
        ValueListenableBuilder<bool>(
          valueListenable: LogService.loggingEnabled,
          builder: (_, logEnabled, __) =>
              ValueListenableBuilder<bool>(
            valueListenable: LogService.errorsOnly,
            builder: (_, errOnly, __) => SettingsToggleRow(
              title: 'Error & Peringatan Saja',
              subtitle: 'Sembunyikan log informasi biasa',
              value: errOnly,
              onChanged: (v) async {
                if (logEnabled) await LogService.setErrorsOnly(v);
              },
            ),
          ),
        ),
        const SettingsDivider(),

        // Log viewer
        ValueListenableBuilder<int>(
          valueListenable: LogService.logCount,
          builder: (_, count, __) => SettingsActionRow(
            title: 'Log Aktivitas',
            trailing: '$count entri',
            onTap: () => _showLogs(context),
          ),
        ),
        const SettingsDivider(),

        // Clear logs
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Log Aktivitas',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                _LogFilterChips(),
              ],
            ),
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
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 4, right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: log.level == LogLevel.error
                                      ? const Color(0xFFF92D48)
                                      : log.level == LogLevel.warning
                                          ? Colors.orange
                                          : const Color(0xFF48484A),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
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
                                        const SizedBox(width: 4),
                                        Text(
                                          '${log.timestamp.hour.toString().padLeft(2,'0')}:'
                                          '${log.timestamp.minute.toString().padLeft(2,'0')}:'
                                          '${log.timestamp.second.toString().padLeft(2,'0')}',
                                          style: const TextStyle(
                                              color: Color(0xFF48484A),
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      log.message,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
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

class _LogFilterChips extends StatefulWidget {
  @override
  State<_LogFilterChips> createState() => _LogFilterChipsState();
}

class _LogFilterChipsState extends State<_LogFilterChips> {
  int _filter = 0; // 0=all, 1=errors, 2=warnings

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(label: 'Semua',    selected: _filter == 0, onTap: () => setState(() => _filter = 0)),
        const SizedBox(width: 4),
        _Chip(label: 'Error',    selected: _filter == 1, onTap: () => setState(() => _filter = 1), color: const Color(0xFFF92D48)),
        const SizedBox(width: 4),
        _Chip(label: 'Warning',  selected: _filter == 2, onTap: () => setState(() => _filter = 2), color: Colors.orange),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = const Color(0xFF8E8E93),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : const Color(0xFF48484A), width: 0.5),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      ),
    );
  }
}

// ─── DEBUG ────────────────────────────────────────────────────────────────────

class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                'DEBUG',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF92D48),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF92D48).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('MODE AKTIF',
                  style: TextStyle(
                      color: Color(0xFFF92D48),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Notification icon picker
        ValueListenableBuilder<int>(
          valueListenable: _DebugState.notifIcon,
          builder: (_, idx, __) => _NotifIconRow(selectedIdx: idx),
        ),
        const SettingsDivider(),

        // Audio session info
        _AudioSessionInfo(),
        const SettingsDivider(),

        // Effect status
        _EffectStatusRow(),
        const SettingsDivider(),

        // Exit debug
        SettingsActionRow(
          title: 'Keluar Mode Debug',
          trailing: '',
          onTap: () => _DebugState.enabled.value = false,
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }
}

class _NotifIconRow extends StatelessWidget {
  final int selectedIdx;
  const _NotifIconRow({required this.selectedIdx});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showIconPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.notifications_none,
                color: Color(0xFF8E8E93), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ikon Notifikasi Pemutar',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    _DebugState.notifIcons[selectedIdx].label,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showIconPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Pilih Ikon Notifikasi'),
        message: const Text('Berlaku setelah restart app'),
        actions: List.generate(
          _DebugState.notifIcons.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == selectedIdx,
            onPressed: () {
              _DebugState.notifIcon.value = i;
              Navigator.of(context).pop();
            },
            child: Text(_DebugState.notifIcons[i].label),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

class _AudioSessionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Info Audio Engine',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          _InfoLine('DSP Pipeline',
              AudioEngine.isAndroid ? 'Android DSP' : 'Web / Fallback'),
          _InfoLine('Virtualizer',
              AudioEngine.virtualizerSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
          _InfoLine('BassBoost',
              AudioEngine.bassBoostSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
          _InfoLine('PresetReverb',
              AudioEngine.reverbSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String val;
  const _InfoLine(this.label, this.val);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: Color(0xFF8E8E93), fontSize: 12)),
          Expanded(
            child: Text(val,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _EffectStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Efek Aktif',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.spatialAudio,
            builder: (_, v, __) =>
                _InfoLine('Spatial', v ? 'ON (${AudioEffectsService.spatialStrength.value})' : 'OFF'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.audioNormalize,
            builder: (_, v, __) => _InfoLine('Normalize', v ? 'ON' : 'OFF'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.bassBoost,
            builder: (_, v, __) => _InfoLine('BassBoost', '$v / 1000'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.reverbPreset,
            builder: (_, v, __) => _InfoLine(
                'Reverb', AudioEffectsService.reverbPresetNames[v]),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, v, __) => ValueListenableBuilder<int>(
              valueListenable: AudioEffectsService.roomPreset,
              builder: (_, r, __) => _InfoLine(
                  'EQ',
                  v
                      ? '${AudioEffectsService.roomPresets[r]['name']} (room)'
                      : 'OFF'),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AudioEffectsService.playbackSpeed,
            builder: (_, v, __) => _InfoLine('Speed', '${v.toStringAsFixed(2)}x'),
          ),
        ],
      ),
    );
  }
}

// ─── TENTANG ─────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('TENTANG'),
        const SizedBox(height: 6),
        const SettingsInfoRow(title: 'Music Player', trailing: '© 2026'),
        const SettingsDivider(),
        // Version — tap 3x to enable debug mode
        _VersionTile(),
        const SettingsDivider(),
      ],
    );
  }
}

class _VersionTile extends StatefulWidget {
  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  int _tapCount = 0;
  DateTime? _firstTap;

  void _onTap() {
    final now = DateTime.now();
    if (_firstTap == null ||
        now.difference(_firstTap!) > const Duration(seconds: 2)) {
      _firstTap = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }

    if (_tapCount >= 3) {
      _tapCount = 0;
      _firstTap = null;
      if (!_DebugState.enabled.value) {
        _DebugState.enabled.value = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mode Debug diaktifkan'),
            backgroundColor: Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<bool>(
        valueListenable: _DebugState.enabled,
        builder: (_, debug, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Versi',
                  style: TextStyle(
                    color: debug ? const Color(0xFFF92D48) : Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                debug ? '1.0.0 [DEBUG]' : '1.0.0',
                style: const TextStyle(
                    color: Color(0xFF8E8E93), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
