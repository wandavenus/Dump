part of '../settings_page.dart';

class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────
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
              child: const Text(
                'MODE AKTIF',
                style: TextStyle(
                  color: Color(0xFFF92D48),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // ── Notification icon picker ─────────────────────────────────────
        ValueListenableBuilder<int>(
          valueListenable: _DebugState.notifIcon,
          builder: (_, idx, __) => _NotifIconRow(selectedIdx: idx),
        ),
        const SettingsDivider(),

        // ── Audio session info ───────────────────────────────────────────
        _AudioSessionInfo(),
        const SettingsDivider(),

        // ── Effect status ────────────────────────────────────────────────
        _EffectStatusRow(),
        const SettingsDivider(),

        // ── Dual-player status ───────────────────────────────────────────
        const _DualPlayerStatus(),
        const SettingsDivider(),

        // ── Exit debug ───────────────────────────────────────────────────
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

// ─── Dual-player status ───────────────────────────────────────────────────────

class _DualPlayerStatus extends StatelessWidget {
  const _DualPlayerStatus();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dual-Player Engine',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 6),
          StreamBuilder<PlayerState>(
            stream: AudioEngine.activePlayer.playerStateStream,
            builder: (_, snap) {
              final state = snap.data;
              return Column(
                children: [
                  _InfoLine(
                    'Slot A (active/standby)',
                    AudioEngine.isAndroid ? 'Android DSP ✓' : 'Web/Fallback',
                  ),
                  _InfoLine(
                    'Crossfade',
                    '${AudioEffectsService.crossfadeDuration.value.toStringAsFixed(1)}s',
                  ),
                  _InfoLine(
                    'Active player state',
                    state?.processingState.name ?? 'idle',
                  ),
                  _InfoLine(
                    'Gapless preload',
                    AudioEffectsService.gaplessPlayback.value ? 'ON ✓' : 'OFF',
                  ),
                  _InfoLine(
                    'Normalization',
                    AudioEffectsService.audioNormalize.value ? 'LUFS −14 dB ✓' : 'OFF',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
