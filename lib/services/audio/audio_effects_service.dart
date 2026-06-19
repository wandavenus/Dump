import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/replay_gain_mode.dart';
import '../log_service.dart';
import 'audio_engine.dart';
import 'media3/media3_audio_player.dart' show AndroidEqualizerParameters;
import 'media3/media3_playback_bridge.dart';

part 'audio_effects_service/service.dart';
