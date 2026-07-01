part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewBuildState on _SyncedLyricsViewState {
  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _buildLyricsView(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification) {
          if (n.direction != ScrollDirection.idle) {
            _userIsManualScrolling = true;
            _scrollResumeTimer?.cancel();
          }
        } else if (n is ScrollEndNotification && _userIsManualScrolling) {
          _scrollResumeTimer?.cancel();
          _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            _userIsManualScrolling = false;
            _scrollToCenter(_currentIndex, animate: true);
          });
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: _settingsListenable,
        builder: (context, _) {
          final double fs = LyricsSettings.fontSize.value;
          final Color active = LyricsSettings.resolvedActiveColor;
          final TextAlign align = LyricsSettings.resolvedTextAlign;
          final bool karaokeOn = LyricsSettings.karaokeMode.value;
          final Color dim = Colors.white.withValues(alpha: 0.35);

          return ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            padding: widget.padding.resolve(TextDirection.ltr),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final isActive = index == _currentIndex;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final targetPos = widget.lyrics[index].timestamp;

                  // Kunci target posisinya di sini beb
                  _pendingSeekPos = targetPos;

                  // ── Optimistic update biar UI langsung loncat duluan ───
                  _anchorPos = targetPos;
                  _anchorWallMs = DateTime.now().millisecondsSinceEpoch;

                  _maybeUpdateCurrentLine(targetPos, allowBinarySearch: true);
                  _karaokeController.updatePosition(targetPos);
                  // ──────────────────────────────────────────────────────

                  AudioService.seek(targetPos);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.bold,
                      color: isActive ? active : dim,
                      height: 1.4,
                    ),
                    child: isActive && karaokeOn
                        ? _UnifiedKaraokeLine(
                            key: ValueKey(_currentIndex),
                            text: widget.lyrics[index].text,
                            timeline: _wordTimelines[index],
                            controller: _karaokeController,
                            activeColor: active,
                            dimColor: dim,
                            fontSize: fs,
                            textAlign: align,
                            textScaleFactor: MediaQuery.textScalerOf(
                              context,
                            ).scale(1.0),
                            textDirection: Directionality.of(context),
                          )
                        : Text(widget.lyrics[index].text, textAlign: align),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
