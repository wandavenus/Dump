// ── ReplayGainService library ─────────────────────────────────────────────────
//
// This file is the library entry point for the ReplayGain subsystem.
// It declares all shared imports and includes the implementation via `part`.
//
// Why a separate entry-point file?
//   The implementation in `replay_gain_service/service.dart` is large (~450 lines)
//   and references multiple packages and local models.  Keeping the import block
//   here lets the part file stay focused on logic rather than dependency
//   management, and makes it easy to add future sub-parts (e.g. a scanner
//   result model) without touching the implementation file.
//
// Public surface: [ReplayGainService] (all static, accessed by PlaybackManager).

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/local_song.dart';
import '../models/loudness_data.dart';
import 'log_service.dart';

part 'replay_gain_service/service.dart';
