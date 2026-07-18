// ── LyricsService library ─────────────────────────────────────────────────────
//
// Library entry point for the lyrics subsystem.
// Declares shared imports and includes sub-parts via `part`.
//
// Public surface: [LyricsService] (all static, accessed by AudioEffectsService
// and the lyrics UI).  Fetch orchestration lives in [LyricsFetchManager].

import '../models/lyric_line.dart';
import 'audio/audio_effects_service.dart';
import 'log_service.dart';
import 'lyrics_service/fetch_manager.dart';
import 'lyrics_service/lrc_parser.dart';
import 'lyrics_service/provider.dart';
import 'lyrics_service/quality.dart';

part 'lyrics_service/source.dart';
part 'lyrics_service/result.dart';
part 'lyrics_service/service.dart';
