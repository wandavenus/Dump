import 'dart:async';

import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../services/download_manager.dart';
import '../../services/extensions/extension_service.dart';
import '../../services/extensions/models/online_track.dart';
import '../../services/media_store_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/sample_music_data.dart';
import '../song_artwork.dart';

// ─── Main entry point ─────────────────────────────────────────────────────────

part 'search_sections/slivers.dart';
part 'search_sections/state.dart';
part 'search_sections/title.dart';
part 'search_sections/bar.dart';
part 'search_sections/results.dart';
part 'search_sections/result_tile.dart';
part 'search_sections/cat_grid.dart';
part 'search_sections/cat_tile.dart';
