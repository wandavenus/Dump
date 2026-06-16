import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/local_song.dart';
import 'audio/audio_effects_service.dart';
import 'audio/audio_engine.dart';
import 'audio/crossfade_controller.dart';
import 'audio/dual_player_manager.dart';
import 'audio/gapless_album_detector.dart';
import 'audio_playback_state.dart';
import 'audio_source_builder.dart';
import 'history_service.dart';
import 'log_service.dart';

part 'audio_service/service.dart';
