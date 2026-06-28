import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_song.dart';
import '../../services/audio_playback_state.dart';
import '../../services/audio_service.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../player/player_panel_controller.dart';
import '../common/scrolling_page_chrome.dart';
import '../song_artwork.dart';

// ─── Data model tiap menu library ─────────────────────────────────────────────

part 'library_sections/item.dart';
part 'library_sections/content.dart';
part 'library_sections/state.dart';
part 'library_sections/header.dart';
part 'library_sections/row.dart';
part 'library_sections/detail.dart';
part 'library_sections/row_edit.dart';
part 'library_sections/editable.dart';
