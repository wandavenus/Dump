import 'dart:async' show unawaited;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

import '../../models/local_song.dart';
import '../../models/playlist.dart';
import '../../utils/constants.dart';
import '../../services/artwork_repository.dart';
import '../../services/media_store_service.dart';
import '../../services/history_service.dart';
import '../../services/playlist_service.dart';
import '../../theme/app_colors.dart';
import '../common/scrolling_page_chrome.dart';
import '../local_song_carousel.dart';
import '../song_artwork.dart';
import '../../pages/playlist_page.dart';
import '../../utils/zoom_fade_route.dart';
import '../common/swipe_to_dismiss_sheet.dart';

part 'browse_sections/content.dart';
part 'browse_sections/state.dart';
part 'browse_sections/banners.dart';
part 'browse_sections/section.dart';
part 'browse_sections/playlist_card.dart';
part 'browse_sections/playlists.dart';
