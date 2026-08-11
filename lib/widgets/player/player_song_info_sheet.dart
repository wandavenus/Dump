import 'dart:async';

import 'package:flutter/material.dart';

import '../../extensions/localization_extension.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

import '../../models/local_song.dart';
import '../../models/song_info.dart';
import '../../services/audio/playback_manager.dart';
import '../../services/song_metadata_service.dart';
import '../common/swipe_to_dismiss_sheet.dart';
import 'player_song_info_row.dart';

part 'player_song_info_sheet/sheet.dart';
part 'player_song_info_sheet/state.dart';
part 'player_song_info_sheet/loading.dart';
part 'player_song_info_sheet/content.dart';
part 'player_song_info_sheet/info.dart';
part 'player_song_info_sheet/file_path.dart';
