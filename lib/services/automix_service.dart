import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_song.dart';
import 'audio_service.dart';
import 'log_service.dart';
import 'replay_gain_service.dart';
import 'audio/audio_effects_service.dart';

part 'automix_service/models.dart';
part 'automix_service/engine.dart';
part 'automix_service/service.dart';
