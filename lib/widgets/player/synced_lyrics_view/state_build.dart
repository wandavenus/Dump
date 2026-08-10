part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewBuildState on _SyncedLyricsViewState {
  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _buildLyricsView(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        liveScrollContext = n.context ?? liveScrollContext;
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
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _settingsListenable,
          _lineTransitionController,
        ]),
        builder: (context, _) {
          final double fs = LyricsSettings.fontSize.value;
          final double lineSpacing = LyricsSettings.lineSpacing.value;
          final Color active = LyricsSettings.resolvedActiveColor;
          final TextAlign align = LyricsSettings.resolvedTextAlign;
          final bool karaokeOn = LyricsSettings.karaokeMode.value;
          final Color dim = Colors.white.withValues(alpha: 0.35);
          final t = Curves.easeOutBack.transform(
            _lineTransitionController.value,
          );
          final direction = _currentIndex >= _previousIndex ? 1.0 : -1.0;

          return ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            scrollOffsetController: widget.offsetController,
            padding: widget.padding.resolve(TextDirection.ltr),
            itemCount: widget.lyrics.length,
            itemBuilder: (context, index) {
              final isActive = index == _currentIndex;
              final lineDirection = LyricsTextDirection.resolve(
                widget.lyrics[index].text,
              );
              final lineAlign = lineDirection == TextDirection.rtl
                  ? TextAlign.right
                  : align;

              // Existing rubber movement: unchanged.
              final distance = (index - _currentIndex).abs().toDouble();
              final distanceFactor = 1.0 / (1.0 + distance * 0.45);
              final phase = Curves.easeOut.transform(
                _lineTransitionController.value,
              );
              final rubber =
                  11.0 * math.sin(math.pi * phase) * distanceFactor;
              final settle = Curves.easeOutBack.transform(
                _lineTransitionController.value,
              );
              final overshoot =
                  2.5 * math.sin(math.pi * 1.5 * settle) * distanceFactor;
              final lead = index < _currentIndex ? 0.72 : 1.0;
              final lineOffset = direction *
                  (rubber + overshoot) *
                  lead *
                  (isActive ? 0.18 : 1.0);

              // Scale pulse follows the same movement order: lines closer to
              // the active line reach their peak earlier; farther lines lag
              // behind. Every line returns to its original 1.0x size.
              final distanceFromActive = (index - _currentIndex).abs();
              final stagger = (distanceFromActive * 0.10).clamp(0.0, 0.45);
              final scaleProgress = ((t - stagger) / (1.0 - stagger))
                  .clamp(0.0, 1.0);
              final scalePulse =
                  math.sin(math.pi * Curves.easeOut.transform(scaleProgress));
              final scale = 1.0 + (0.045 * scalePulse);

              return Transform.translate(
                offset: Offset(0, lineOffset),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final targetPos = widget.lyrics[index].timestamp;
                      _pendingSeekPos = targetPos;
                      _anchorPos = targetPos;
                      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
                      _maybeUpdateCurrentLine(
                        targetPos,
                        allowBinarySearch: true,
                      );
                      _karaokeController.updatePosition(targetPos);
                      unawaited(AudioService.seek(targetPos));
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: lineSpacing),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
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
                                textAlign: lineAlign,
                                textScaleFactor: MediaQuery.textScalerOf(
                                  context,
                                ).scale(1.0),
                                textDirection: lineDirection,
                              )
                            : Text(
                                widget.lyrics[index].text,
                                textAlign: lineAlign,
                                textDirection: lineDirection,
                              ),
                      ),
                    ),
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
