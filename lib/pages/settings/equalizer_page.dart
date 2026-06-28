import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/audio/audio_effects_service.dart';
import '../../services/audio/audio_engine.dart';
import '../../services/audio/media3/media3_playback_bridge.dart';
import '../../themes/theme_controller.dart';

part 'equalizer_page/page.dart';
part 'equalizer_page/band_slider.dart';
part 'equalizer_page/room_grid.dart';
