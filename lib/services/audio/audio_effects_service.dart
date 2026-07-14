import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:native_audio_runtime/native_audio_runtime.dart' show PeqFilterType;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/replay_gain_mode.dart';
import '../log_service.dart';
import 'playback_manager.dart';

part 'audio_effects_service/service.dart';
