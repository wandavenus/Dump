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
