part of '../settings_page.dart';

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
                color: const Color(0xFFF92D48).withValues(alpha: 0.15),
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

        // ── Simulasi Player ─────────────────────────────────────────────────
        const _SimulationSection(),
        const SettingsDivider(),

        // Notification icon picker
        ValueListenableBuilder<int>(
          valueListenable: _DebugState.notifIcon,
          builder: (_, idx, _) => _NotifIconRow(selectedIdx: idx),
        ),
        const SettingsDivider(),

        // Audio session info
        _AudioSessionInfo(),
        const SettingsDivider(),

        // Effect status
        _EffectStatusRow(),
        const SettingsDivider(),

        // Audio Offload real-time status
        const _OffloadStatusInfo(),
        const SettingsDivider(),

        // Exit debug
        SettingsActionRow(
          title: 'Keluar Mode Debug',
          trailing: '',
          onTap: () {
            PlaybackSimulationService.stop();
            PlayerSheetController.close();
            _DebugState.enabled.value = false;
          },
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }
}

// ─── Simulation Section ────────────────────────────────────────────────────────

class _SimulationSection extends StatelessWidget {
  const _SimulationSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlaybackSimulationService.active,
      builder: (context, isActive, _) {
        return Column(
          children: [
            SettingsToggleRow(
              title: 'Simulasi Player',
              subtitle: isActive
                  ? 'Aktif — mini player & player sheet dapat dilihat'
                  : 'Tampilkan mini player & player sheet tanpa audio nyata',
              value: isActive,
              onChanged: (val) async {
                if (val) {
                  PlaybackSimulationService.start();
                  await Future.delayed(const Duration(milliseconds: 80));
                  PlayerSheetController.open();
                } else {
                  PlayerSheetController.close();
                  PlaybackSimulationService.stop();
                }
              },
            ),
            if (isActive) ...[
              const SizedBox(height: 2),
              _SimulationControls(),
            ],
          ],
        );
      },
    );
  }
}

// ─── Simulation Controls Card ─────────────────────────────────────────────────

class _SimulationControls extends StatelessWidget {
  const _SimulationControls();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        final song     = state.currentSong;
        final position = state.position;
        final duration = state.duration;
        final playing  = state.isPlaying;

        final posStr = _fmt(position);
        final durStr = _fmt(duration);
        final progress = duration.inSeconds == 0
            ? 0.0
            : (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF92D48).withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Song info
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF92D48).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: Color(0xFFF92D48), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.title ?? '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song != null
                              ? '${song.artist} · ${song.album}'
                              : '—',
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${state.currentIndex + 1}/${PlaybackSimulationService.songs.length}',
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 11),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFF92D48)),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(posStr,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 10)),
                  Text(durStr,
                      style: const TextStyle(
                          color: Color(0xFF8E8E93), fontSize: 10)),
                ],
              ),

              const SizedBox(height: 10),

              // Transport controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CtrlBtn(
                    icon: Icons.skip_previous_rounded,
                    onTap: PlaybackSimulationService.skipPrev,
                  ),
                  const SizedBox(width: 16),
                  _CtrlBtn(
                    icon: playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    size: 40,
                    onTap: PlaybackSimulationService.togglePlayPause,
                    color: const Color(0xFFF92D48),
                  ),
                  const SizedBox(width: 16),
                  _CtrlBtn(
                    icon: Icons.skip_next_rounded,
                    onTap: PlaybackSimulationService.skipNext,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Song list quick-jump
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List.generate(
                  PlaybackSimulationService.songs.length,
                  (i) {
                    final s = PlaybackSimulationService.songs[i];
                    final isCurrent = i == state.currentIndex;
                    return GestureDetector(
                      onTap: () {
                        if (!isCurrent) {
                          PlaybackSimulationService.jumpToSong(i);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFFF92D48).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: isCurrent
                              ? Border.all(
                                  color: const Color(0xFFF92D48)
                                      .withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Text(
                          s.title,
                          style: TextStyle(
                            color: isCurrent
                                ? const Color(0xFFF92D48)
                                : const Color(0xFF8E8E93),
                            fontSize: 10,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─── Control button ───────────────────────────────────────────────────────────

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;

  const _CtrlBtn({
    required this.icon,
    required this.onTap,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: size),
    );
  }
}
