import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/utils/zoom_fade_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../common/scrolling_page_chrome.dart';
import '../common_actions.dart';
import '../play_shuffle_buttons.dart';
import '../song_artwork.dart';
import '../song_context_menu.dart';
import 'artist_list_sections.dart';

// ─── Data model tiap menu library ─────────────────────────────────────────────

part 'library_sections/item.dart';
part 'library_sections/content.dart';
part 'library_sections/state.dart';
part 'library_sections/header.dart';
part 'library_sections/row.dart';
part 'library_sections/detail.dart';
part 'library_sections/row_edit.dart';
part 'library_sections/editable.dart';
