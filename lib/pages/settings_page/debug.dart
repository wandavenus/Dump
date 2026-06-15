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

        // ── Sample audio tracks ──────────────────────────────────────────
        const _SampleTracksSection(),
        const SettingsDivider(),

        // ── Exit debug ───────────────────────────────────────────────────
        SettingsActionRow(
          title: 'Keluar Mode Debug',
          trailing: '',
          onTap: () async {
            await _DebugState.stopSample();
            _DebugState.enabled.value = false;
          },
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

// ─── Sample tracks ────────────────────────────────────────────────────────────

class _SampleTracksSection extends StatelessWidget {
  const _SampleTracksSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Sample Audio (SoundHelix)',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              const Spacer(),
              ValueListenableBuilder<int>(
                valueListenable: _DebugState.playingSample,
                builder: (_, idx, __) => idx >= 0
                    ? GestureDetector(
                        onTap: _DebugState.stopSample,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'Stop',
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<String>(
            valueListenable: _DebugState.sampleStatus,
            builder: (_, status, __) => status.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          ...List.generate(
            _DebugState.samples.length,
            (i) => _SampleTrackRow(index: i),
          ),
        ],
      ),
    );
  }
}

class _SampleTrackRow extends StatelessWidget {
  final int index;
  const _SampleTrackRow({required this.index});

  @override
  Widget build(BuildContext context) {
    final sample = _DebugState.samples[index];

    return ValueListenableBuilder<int>(
      valueListenable: _DebugState.playingSample,
      builder: (_, playing, __) {
        final isPlaying = playing == index;
        final isLoading = isPlaying && _DebugState.sampleLoading.value;

        return InkWell(
          onTap: isPlaying
              ? _DebugState.stopSample
              : () => _DebugState.playSample(index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                // Play / Stop button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? const Color(0xFF1DB954).withOpacity(0.25)
                        : Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                    border: isPlaying
                        ? Border.all(color: const Color(0xFF1DB954).withOpacity(0.6))
                        : null,
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFF1DB954),
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          size: 18,
                          color: isPlaying
                              ? const Color(0xFF1DB954)
                              : Colors.white.withOpacity(0.7),
                        ),
                ),
                const SizedBox(width: 12),
                // Title + genre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sample.title,
                        style: TextStyle(
                          color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
                          fontSize: 13,
                          fontWeight: isPlaying
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      Text(
                        sample.genre,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'MP3 · Web',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
