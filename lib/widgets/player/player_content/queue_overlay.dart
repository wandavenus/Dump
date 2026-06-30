part of '../player_content.dart';

// ─── Queue overlay body ───────────────────────────────────────────────────────

class _QueueOverlayBody extends StatefulWidget {
  final bool isVisible;
  final VoidCallback onClose;
  final ScrollController scrollController;

  const _QueueOverlayBody({
    required this.isVisible,
    required this.onClose,
    required this.scrollController,
  });

  @override
  State<_QueueOverlayBody> createState() => _QueueOverlayBodyState();
}

class _QueueOverlayBodyState extends State<_QueueOverlayBody> {
  bool _autoplayEnabled = false;

  @override
  void didUpdateWidget(_QueueOverlayBody old) {
    super.didUpdateWidget(old);
    // Auto-scroll to current track when the overlay becomes visible.
    if (widget.isVisible && !old.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!widget.scrollController.hasClients) return;
    final idx = AudioService.playbackState.value.currentIndex;
    if (idx <= 0) return;
    // Standard ListTile height (with subtitle) is ~72 px.
    // Scroll so the item above current is visible, centring the current row.
    const itemH = 72.0;
    final target = ((idx - 1) * itemH).clamp(
      0.0,
      widget.scrollController.position.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlaybackState>(
      valueListenable: AudioService.playbackState,
      builder: (context, state, _) {
        if (state.currentPlaylist.isEmpty) {
          return Center(
            child: Text(
              'Antrian kosong',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 15,
              ),
            ),
          );
        }

        final playlist = state.currentPlaylist;
        final currentIdx = state.currentIndex;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _QueueControlButton(
                      icon: CupertinoIcons.shuffle,
                      active: state.shuffleEnabled,
                      onTap: AudioService.toggleShuffle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QueueControlButton(
                      icon:
                          state.loopMode == LoopMode.one
                              ? CupertinoIcons.repeat_1
                              : CupertinoIcons.repeat,
                      active: state.loopMode != LoopMode.off,
                      onTap: AudioService.cycleLoopMode,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QueueControlButton(
                      icon: CupertinoIcons.infinite,
                      active: _autoplayEnabled,
                      onTap:
                          () => setState(
                            () => _autoplayEnabled = !_autoplayEnabled,
                          ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 17),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lanjutkan Memutar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 0.5),
                  Text(
                    'Memutar otomatis musik serupa',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            Expanded(
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.60, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: ReorderableListView.builder(
                  scrollController: widget.scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  dragStartBehavior: DragStartBehavior.down,
                  itemCount: playlist.length,
                  onReorder: AudioService.reorderQueue,
                  itemBuilder: (context, index) {
                    final song = playlist[index];
                    final isCurrent = index == currentIdx;
                    return _QueueRow(
                      key: ValueKey('queue_${song.id}_$index'),
                      index: index,
                      song: song,
                      isCurrent: isCurrent,
                      onTap: () {
                        AudioService.playFromCurrentQueue(index);
                        widget.onClose();
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Single queue row ─────────────────────────────────────────────────────────

class _QueueRow extends StatelessWidget {
  final int index;
  final LocalSong song;
  final bool isCurrent;
  final VoidCallback onTap;

  const _QueueRow({
    super.key,
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white10,
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Leading: equalizer icon for current, artwork for others
              SizedBox(
                width: 44,
                height: 44,
                child: SongArtwork(
                  songId: song.id,
                  size: 44,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              // Title + artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            isCurrent ? const Color(0xFFFFFFFF) : Colors.white,
                        fontSize: 14,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Drag handle
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
