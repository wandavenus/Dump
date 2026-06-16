part of '../player_secondary_controls.dart';

class PlayerSecondaryControls extends StatelessWidget {
  final LocalSong song;
  final bool showLyrics;
  final VoidCallback onLyricsToggle;

  const PlayerSecondaryControls({
    super.key,
    required this.song,
    required this.showLyrics,
    required this.onLyricsToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LyricsToggleButton(
            active: showLyrics,
            onTap: onLyricsToggle,
          ),
          const SizedBox(width: 150),
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(CupertinoIcons.list_bullet, size: 24),
            tooltip: 'Antrian',
          ),
        ],
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
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
              const Text(
                'Antrian',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder<AudioPlaybackState>(
                  valueListenable: AudioService.playbackState,
                  builder: (context, state, _) {
                    if (state.currentPlaylist.isEmpty) {
                      return const Center(
                        child: Text(
                          'Antrian kosong',
                          style: TextStyle(color: Color(0xFF8E8E93)),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: sc,
                      itemCount: state.currentPlaylist.length,
                      itemBuilder: (context, index) {
                        final s = state.currentPlaylist[index];
                        final isCurrent = index == state.currentIndex;
                        return ListTile(
                          onTap: () =>
                              AudioService.playFromCurrentQueue(index),
                          leading: isCurrent
                              ? const Icon(Icons.equalizer,
                                  color: Color(0xFFF92D48))
                              : null,
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFFF92D48)
                                  : Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(color: Color(0xFF8E8E93)),
                          ),
                        );
                      },
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
}

// ─── Lyrics toggle button with active-state highlight ───────────────────────

class _LyricsToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _LyricsToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          CupertinoIcons.quote_bubble,
          size: 24,
          color: active ? const Color(0xFFF92D48) : Colors.white,
        ),
      ),
    );
  }
}
