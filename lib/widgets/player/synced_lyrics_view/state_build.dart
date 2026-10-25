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
          final Color dim = Colors.white.withValues(alpha: 0.48);
          final motionDisabled = MediaQuery.disableAnimationsOf(context);
          final motionDuration = motionDisabled
              ? Duration.zero
              : lyricFocusAnimationDuration;

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

              final distance = (index - _currentIndex).abs();
              final targetBlur = lyricFocusBlurSigma(distance);
              final scrollDistance =
                  ((_currentIndex - _previousIndex) * 16.0)
                      .clamp(-96.0, 96.0)
                      .toDouble();
              final lineOffset = motionDisabled
                  ? 0.0
                  : lyricStaggeredRowOffset(
                      animationProgress: _lineTransitionController.value,
                      distance: scrollDistance,
                      rowsAfterFocus: index - _currentIndex,
                    );

              return Transform.translate(
                offset: Offset(0, lineOffset),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final targetPos = widget.lyrics[index].timestamp;
                    _pendingSeekPos = targetPos;
                    _anchorPos = targetPos;
                    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
                    _maybeUpdateCurrentLine(targetPos, allowBinarySearch: true);
                    _karaokeController.updatePosition(targetPos);
                    unawaited(AudioService.seek(targetPos));
                  },
                  child: AnimatedOpacity(
                    opacity: isActive ? 1.0 : 0.48,
                    duration: motionDuration,
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: isActive ? 1.0 : 0.96,
                      duration: motionDuration,
                      curve: Curves.easeInOutCubic,
                      child: _AnimatedLyricBlur(
                        sigma: targetBlur,
                        duration: motionDuration,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: lineSpacing),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            style: TextStyle(
                              fontSize: fs,
                              fontWeight: FontWeight.bold,
                              color: isActive ? active : Colors.white,
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

/// Keeps the animated blur's controller alive while the parent list repaints
/// for lyric-clock updates. Repeated parent builds must not restart the tween.
class _AnimatedLyricBlur extends StatefulWidget {
  const _AnimatedLyricBlur({
    required this.sigma,
    required this.duration,
    required this.child,
  });

  final double sigma;
  final Duration duration;
  final Widget child;

  @override
  State<_AnimatedLyricBlur> createState() => _AnimatedLyricBlurState();
}

class _AnimatedLyricBlurState extends State<_AnimatedLyricBlur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1;
    _animation = AlwaysStoppedAnimation<double>(widget.sigma);
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sigma == widget.sigma &&
        oldWidget.duration == widget.duration) {
      return;
    }

    final currentSigma = _animation.value;
    _controller.stop();
    _controller.duration = widget.duration;
    if (widget.duration == Duration.zero) {
      _controller.value = 1;
      _animation = AlwaysStoppedAnimation<double>(widget.sigma);
      return;
    }

    _animation = Tween<double>(
      begin: currentSigma,
      end: widget.sigma,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final sigma = _animation.value;
      if (sigma <= 0.01) return child!;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      );
    },
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
