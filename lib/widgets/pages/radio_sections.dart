import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import '../../utils/constants.dart';
import '../../utils/zoom_fade_route.dart';

import '../../models/playlist.dart';
import '../../pages/playlist_page.dart';
import '../../services/artwork_repository.dart';
import '../../services/playlist_service.dart';
import '../../theme/app_colors.dart';
import '../common/scrolling_page_chrome.dart';
import '../common/swipe_to_dismiss_sheet.dart';
import '../song_artwork.dart';

part 'radio_sections/content.dart';
part 'radio_sections/stations.dart';
part 'radio_sections/station_card.dart';
