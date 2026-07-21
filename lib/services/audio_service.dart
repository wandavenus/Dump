// ── AudioService library ──────────────────────────────────────────────────────
//
// Library entry point for the high-level audio playback service.
// Aggregates imports used by all sub-parts and exposes the implementation
// via `part 'audio_service/service.dart'`.
//
// Public surface: [AudioService] (all static, facade over PlaybackManager).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'audio/playback_manager.dart';

import '../models/local_song.dart';
import '../models/replay_gain_mode.dart';
import 'audio/audio_effects_service.dart';
import 'audio/device_dsp.dart';
import 'artwork_repository.dart';
import 'audio_playback_state.dart';
import 'media_store_service.dart';
import 'history_service.dart';
import 'log_service.dart';
import 'loudness_source_resolver.dart';
import 'boot_trace.dart';

part 'audio_service/service.dart';
part 'audio_service/replay_gain_applicator.dart';
