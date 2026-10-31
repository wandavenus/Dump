part of '../synced_lyrics_view.dart';

extension _SyncedLyricsViewBuildState on _SyncedLyricsViewState {
  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _buildLyricsView(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        liveScrollContext = n.context ?? liveScrollContext;
        final externalDrag = widget.dragHandle?.isExternalDragActive == true;
        final dragUpdate =
            n is ScrollUpdateNotification &&
            (n.dragDetails != null || externalDrag);
        final activeUserScroll =
            n is UserScrollNotification && n.direction != ScrollDirection.idle;

        if (activeUserScroll || dragUpdate) {
          _beginManualLyricsScroll();
        } else if (n is ScrollEndNotification && _userIsManualScrolling) {
          _scheduleAutomaticLyricsReturn();
        }
        return false;
      },
      child: ListenableBuilder(
        listenable: _settingsListenable,
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final resolvedPadding = widget.padding.resolve(TextDirection.ltr);
              _prepareKaraokeLayouts(
                constraints.maxWidth - resolvedPadding.horizontal,
              );
              return ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            scrollOffsetController: widget.offsetController,
            padding: resolvedPadding,
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
              final scrollDistance = ((_currentIndex - _previousIndex) * 16.0)
                  .clamp(-96.0, 96.0)
                  .toDouble();

              // Keep the staggered motion local to each visible row. Listening
              // above caused the entire ScrollablePositionedList subtree to
              // rebuild on every animation tick.
              return AnimatedBuilder(
                animation: _lineTransitionController,
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
                        visibility: _blurVisibility,
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
                            child: karaokeReady
                                ? _UnifiedKaraokeLine(
                                    key: ValueKey(_currentIndex),
                                    text: widget.lyrics[index].text,
                                    lineIndex: index,
                                    timeline: _wordTimelines[index],
                                    wordTexts: _wordTextTimelines[index],
                                    layoutCache: _karaokeLayoutCache,
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
                builder: (context, child) {
                  final lineOffset = motionDisabled
                      ? 0.0
                      : lyricStaggeredRowOffset(
                          animationProgress: _lineTransitionController.value,
                          distance: scrollDistance,
                          rowsAfterFocus: index - _currentIndex,
                        );
                  return Transform.translate(
                    offset: Offset(0, lineOffset),
                    child: child,
                  );
                },
              );
              },
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
    required this.visibility,
    required this.child,
  });

  final double sigma;
  final Duration duration;
  final Animation<double> visibility;
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

    _animation = Tween<double>(begin: currentSigma, end: widget.sigma).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => AnimatedBuilder(
      animation: widget.visibility,
      child: child,
      builder: (context, child) {
        final sigma = _animation.value * widget.visibility.value;
        if (sigma <= 0.01) return child!;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      },
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
