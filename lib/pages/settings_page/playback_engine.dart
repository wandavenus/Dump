part of '../settings_page.dart';

// ─── Playback Engine Section ───────────────────────────────────────────────────

class _PlaybackEngineSection extends StatelessWidget {
  const _PlaybackEngineSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Engine Selector ──────────────────────────────────────────────────
        const SettingsSectionHeader('Engine Pemutaran'),
        const SizedBox(height: 6),
        const _EngineSelector(),
        const SettingsDivider(),

        // ── Engine Tunneling — hanya tampil saat Native Media3 aktif ─────────
        ValueListenableBuilder<PlaybackEngineType>(
          valueListenable: AudioEngineManager.activeEngineType,
          builder: (_, engine, _) {
            if (engine != PlaybackEngineType.media3) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                const SettingsSectionHeader('Engine Tunneling'),
                const SizedBox(height: 6),

                // ── Skip Silence ─────────────────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable: MediaCapabilitiesService.skipSilenceEnabled,
                  builder: (_, v, _) => SettingsToggleRow(
                    title: 'Gapless',
                    subtitle: 'Potong keheningan antar lagu secara otomatis',
                    value: v,
                    onChanged: MediaCapabilitiesService.setSkipSilence,
                  ),
                ),
                const SettingsDivider(),

                // ── Stereo Widening ──────────────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable: MediaCapabilitiesService.stereoWideningEnabled,
                  builder: (_, enabled, _) => Column(
                    children: [
                      SettingsToggleRow(
                        title: 'Pelebaran Stereo',
                        subtitle:
                            'ChannelMixingAudioProcessor — memperlebar medan stereo',
                        value: enabled,
                        onChanged: MediaCapabilitiesService.setStereoWidening,
                      ),
                      if (enabled)
                        ValueListenableBuilder<double>(
                          valueListenable:
                              MediaCapabilitiesService.stereoWideningStrength,
                          builder: (_, v, _) {
                            final pct = (v * 100).round();
                            return SettingsSliderRow(
                              title: 'Lebar Stereo',
                              subtitle: '$pct%',
                              value: v,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              onChanged:
                                  MediaCapabilitiesService.setStereoWideningStrength,
                              showReset: v != 0.5,
                              onReset: () => MediaCapabilitiesService
                                  .setStereoWideningStrength(0.5),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SettingsDivider(),

                // ── Playback Stats ───────────────────────────────────────────
                SettingsActionRow(
                  title: 'Statistik Sesi',
                  trailing: 'Lihat',
                  onTap: () => _showStatsSheet(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showStatsSheet(BuildContext context) {
    MediaCapabilitiesService.getPlaybackStats().then((stats) {
      if (!context.mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _PlaybackStatsSheet(stats: stats),
      );
    });
  }
}

// ─── Engine Selector Widget ────────────────────────────────────────────────────

class _EngineSelector extends StatelessWidget {
  const _EngineSelector();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackEngineType>(
      valueListenable: AudioEngineManager.activeEngineType,
      builder: (_, active, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AudioEngineManager.isSwitching,
          builder: (_, switching, _) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Column(
                children: [
                  ...PlaybackEngineType.values.map((type) {
                    final isActive = type == active;
                    final isLast = type == PlaybackEngineType.values.last;
                    return Column(
                      children: [
                        _EngineOption(
                          type: type,
                          isSelected: isActive,
                          isSwitching: switching,
                          onTap: switching || isActive
                              ? null
                              : () => _switchEngine(context, type),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                            indent: 56,
                          ),
                      ],
                    );
                  }),
                  if (switching)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFFC3C44),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Berpindah engine…',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _switchEngine(BuildContext context, PlaybackEngineType target) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EngineSwitchConfirmSheet(target: target),
    );
  }
}

class _EngineOption extends StatelessWidget {
  const _EngineOption({
    required this.type,
    required this.isSelected,
    required this.isSwitching,
    required this.onTap,
  });

  final PlaybackEngineType type;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (type) {
      PlaybackEngineType.media3 =>
        'Android Media3 / ExoPlayer — DSP, crossfade, efek native',
      PlaybackEngineType.mediaKit =>
        'media_kit 1.2.6 — cross-platform, pitch/EQ terbatas',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFC3C44)
                      : Colors.white30,
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFFFC3C44)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.displayName,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFFFC3C44)
                          : Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC3C44).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFC3C44).withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: const Text(
                  'Aktif',
                  style: TextStyle(
                    color: Color(0xFFFC3C44),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Konfirmasi Perpindahan Engine ────────────────────────────────────────────

class _EngineSwitchConfirmSheet extends StatelessWidget {
  const _EngineSwitchConfirmSheet({required this.target});
  final PlaybackEngineType target;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
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
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Beralih ke ${target.displayName}?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Queue, posisi, shuffle, dan repeat akan disimpan dan di-restore. '
              'Perpindahan membutuhkan beberapa detik.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
            ),
          ),
          if (target == PlaybackEngineType.mediaKit) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Efek audio (EQ, Bass Boost, Reverb) tidak aktif di engine ini.',
                      style: TextStyle(color: Colors.orange, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Batal',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      AudioEngineManager.switchEngine(target);
                    },
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFC3C44),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Beralih',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Playback Stats Bottom Sheet ──────────────────────────────────────────────

class _PlaybackStatsSheet extends StatelessWidget {
  const _PlaybackStatsSheet({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Statistik Sesi Pemutaran',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<PlaybackEngineType>(
                valueListenable: AudioEngineManager.activeEngineType,
                builder: (_, type, _) => Text(
                  'Engine aktif: ${type.displayName}',
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (stats == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Data tidak tersedia — mulai pemutaran terlebih dahulu.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            )
          else ...[
            _StatRow(
              label: 'Waktu Putar',
              value: _fmtMs((stats!['totalPlayTimeMs'] as num?)?.toInt() ?? 0),
              icon: Icons.play_circle_outline_rounded,
            ),
            _StatRow(
              label: 'Waktu Buffering',
              value: _fmtMs((stats!['totalBufferingTimeMs'] as num?)?.toInt() ?? 0),
              icon: Icons.hourglass_bottom_rounded,
            ),
            _StatRow(
              label: 'Rebuffer',
              value: '${(stats!['totalRebufferCount'] as num?)?.toInt() ?? 0} kali',
              icon: Icons.cached_rounded,
            ),
            _StatRow(
              label: 'Error',
              value: '${(stats!['totalErrorCount'] as num?)?.toInt() ?? 0} kali',
              icon: Icons.error_outline_rounded,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _fmtMs(int ms) {
    if (ms <= 0) return '0 dtk';
    final total = Duration(milliseconds: ms);
    final h = total.inHours;
    final m = total.inMinutes.remainder(60);
    final s = total.inSeconds.remainder(60);
    if (h > 0) return '${h}j ${m}m ${s}d';
    if (m > 0) return '${m}m ${s}d';
    return '${s}d';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF8E8E93)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
