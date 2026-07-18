// ── AudioSessionHandler library ───────────────────────────────────────────────
//
// This file is the library entry point for audio session management.
// It declares all shared imports and includes the implementation via `part`.
//
// Why a separate entry-point file?
//   The `audio_session` package import is needed only by `handler.dart`.
//   Keeping it here isolates the dependency from callers and matches the
//   established pattern used across this codebase (e.g. ReplayGainService,
//   LyricsService, MediaCapabilitiesService).
//
// Public surface: [AudioSessionHandler] (singleton, initialized by PlaybackManager).

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../log_service.dart';

part 'audio_session_handler/handler.dart';
