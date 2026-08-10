import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../models/lyric_line.dart';
import '../../models/lyrics_settings.dart';
import '../../services/audio_service.dart';
import '../../services/audio_playback_state.dart';
import '../../utils/lyrics_text_direction.dart';

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
/// exposes publicly) always drives the scroll via an animated scroll. The
/// handle bypasses that path for forwarded drag gestures so the lyrics track
/// the finger 1:1.
