part of '../synced_lyrics_view.dart';

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final ScrollController _scroll = ScrollController();
  int _currentIndex = 0;

  // Tinggi rata-rata tiap baris — dihitung ulang saat font size berubah
  double _itemHeight = 52.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, fs, __) =>
          ValueListenableBuilder<String>(
        valueListenable: LyricsSettings.textAlign,
        builder: (_, align, __) =>
            ValueListenableBuilder<String>(
          valueListenable: LyricsSettings.activeColor,
          builder: (_, colorKey, __) {
            final activeColor = LyricsSettings.resolvedActiveColor;
            final textAlign   = LyricsSettings.resolvedTextAlign;

            return StreamBuilder<Duration>(
              stream: AudioService.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                _updateCurrentLine(position, fs);

                return ListView.builder(
                  controller: _scroll,
                  padding: widget.padding,
                  itemCount: widget.lyrics.length,
                  itemBuilder: (context, index) {
                    final active = index == _currentIndex;
                    final activeFontSize = fs;
                    final inactiveFontSize = (fs * 0.82).clamp(12.0, 22.0).toDouble();

                    // ⭐ KUNCI: Key berdasarkan index agar widget direuse
                    return Padding(
                      key: ValueKey(index),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: active ? activeFontSize : inactiveFontSize,
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.w400,
                          color: active
                              ? activeColor
                              : Colors.white.withValues(alpha: 0.35),
                          height: 1.4,
                        ),
                        child: Text(
                          widget.lyrics[index].text,
                          textAlign: textAlign,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _updateCurrentLine(Duration position, double fontSize) {
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

    // Update tinggi item sebelum scroll
    _itemHeight = _computeItemHeight(fontSize);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentIndex = activeIndex);
      _scrollToIndex(activeIndex);
    });
  }

  double _computeItemHeight(double fontSize) {
    // Line-height: fontSize * 1.4 (dari style.height)
    // Vertical padding: 6 + 6 = 12
    return fontSize * 1.4 + 12.0;
  }

  void _scrollToIndex(int index) {
    if (!_scroll.hasClients) return;

    final viewportHalf = _scroll.position.viewportDimension / 2;
    final itemOffset = index * _itemHeight;
    final target = (itemOffset - viewportHalf + _itemHeight / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);

    // Hanya scroll jika jarak cukup signifikan
    final currentOffset = _scroll.offset;
    if ((target - currentOffset).abs() > 1.0) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }
}
