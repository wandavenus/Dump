part of '../player_secondary_controls.dart';

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
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
                    final s         = state.currentPlaylist[index];
                    final isCurrent = index == state.currentIndex;
                    return ListTile(
                      onTap: () => AudioService.playFromCurrentQueue(index),
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
                        style: const TextStyle(color: Color(0xFF8E8E93)),
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
  }
}
