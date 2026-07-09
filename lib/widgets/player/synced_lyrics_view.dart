import 'dart:async';
import 'package:flutter/rendering.dart';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../models/lyric_line.dart';
import '../../models/lyrics_settings.dart';
import '../../services/audio_service.dart';
import '../../services/audio_playback_state.dart';

part 'synced_lyrics_view/elrc_word.dart';
part 'synced_lyrics_view/view.dart';
part 'synced_lyrics_view/state.dart';
part 'synced_lyrics_view/state_timeline.dart';
part 'synced_lyrics_view/state_playback.dart';
part 'synced_lyrics_view/state_indexing.dart';
part 'synced_lyrics_view/state_scroll.dart';
part 'synced_lyrics_view/state_build.dart';
part 'synced_lyrics_view/karaoke_controller.dart';
part 'synced_lyrics_view/karaoke_line.dart';
part 'synced_lyrics_view/karaoke_line_painter.dart';

/// Lightweight handle for forwarding raw drag deltas directly into whichever
/// [ScrollPosition] is currently live inside a [SyncedLyricsView].
///
/// [ScrollOffsetController.animateScroll] (the mechanism `scrollable_positioned_list`
/// exposes publicly) always drives the scroll via an animated
/// `DrivenScrollActivity`, even with `Duration.zero` — there is no direct
/// `jumpTo`-equivalent on it. Calling it once per drag-update event spins up a
/// fresh animation every time, which feels laggy/rigid compared to a real
/// finger-tracking scroll. This handle instead captures the actual
/// [BuildContext] of the live internal `Scrollable` (via `ScrollNotification.context`)
/// and calls [ScrollPosition.jumpTo] on it directly — the same primitive a
/// normal drag-to-scroll list uses, so it tracks the finger 1:1 and fires the
/// same scroll notifications a genuine user scroll would.
class LyricsDragHandle {
  _SyncedLyricsViewState? _state;

  /// True while a drag forwarded from outside the list (e.g. the bottom
  /// hit-box areas / gesture-inset relay in content.dart and
  /// player_sheet/state.dart) is in progress. Forwarded drags drive the list
  /// via [ScrollPosition.jumpTo], which produces [ScrollUpdateNotification]s
  /// with `dragDetails == null` (only real drags directly on the Scrollable
  /// carry non-null dragDetails) — so listeners that need to distinguish
  /// "genuine user gesture" from "programmatic scroll" (e.g. auto-follow)
  /// must also check this flag, not just `dragDetails != null`.
  bool isExternalDragActive = false;

  void _attach(_SyncedLyricsViewState state) => _state = state;

  void _detach(_SyncedLyricsViewState state) {
    if (_state == state) _state = null;
  }

  /// Scrolls the live list by [deltaY] pixels (positive = finger moved down,
  /// content should move up — matches the sign convention of
  /// [DragUpdateDetails.delta.dy]).
  void scrollByDelta(double deltaY) => _state?._jumpByDelta(deltaY);

  /// Releases the live list into a normal ballistic fling on drag-release,
  /// so a forwarded drag decelerates naturally instead of stopping dead —
  /// matching the feel of scrolling the list directly. [primaryVelocity] is
  /// the raw on-screen finger velocity (e.g. from
  /// `DragEndDetails.primaryVelocity`); this negates it internally to match
  /// [scrollByDelta]'s sign convention.
  void flingByVelocity(double primaryVelocity) =>
      _state?._flingByVelocity(-primaryVelocity);
}
