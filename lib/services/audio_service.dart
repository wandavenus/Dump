import 'dart:async';

import 'package:flutter/foundation.dart';
import 'audio/media3/media3_audio_player.dart';
import 'audio/media3/media3_playback_bridge.dart';

import '../models/local_song.dart';
import '../models/replay_gain_mode.dart';
import 'audio/audio_effects_service.dart';
import 'audio/audio_engine.dart';
import 'audio/background_audio_handler.dart';
import 'audio/crossfade_controller.dart';
import 'audio/dual_player_manager.dart';
import 'audio/gapless_album_detector.dart';
import 'audio_playback_state.dart';
import 'audio_source_builder.dart';
import 'history_service.dart';
import 'log_service.dart';
import 'loudness_source_resolver.dart';

part 'audio_service/service.dart';
