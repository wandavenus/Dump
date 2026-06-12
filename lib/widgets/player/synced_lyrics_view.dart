import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';
import '../../services/audio_service.dart';

class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scrollController = ScrollController();

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;

        _updateCurrentLine(position);

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          itemCount: widget.lyrics.length,
          itemBuilder: (context, index) {
            final active = index == _currentIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                widget.lyrics[index].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: active ? 24 : 20,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? Colors.white : Colors.white54,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateCurrentLine(Duration position) {
    if (widget.lyrics.isEmpty) return;

    int activeIndex = 0;

    for (int i = 0; i < widget.lyrics.length; i++) {
      if (widget.lyrics[i].timestamp <= position) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex == _currentIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _currentIndex = activeIndex;
      });

      final targetOffset = activeIndex * 44.0;

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          targetOffset.clamp(
            0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
