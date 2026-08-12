import 'dart:async';

// ── EqualizerPage library ─────────────────────────────────────────────────────
//
// Library entry point for the equalizer settings page.
// Declares shared imports used by all sub-parts and includes them via `part`.
//
// Public surface: [EqualizerPage] (StatefulWidget navigated from Settings).

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/audio/audio_effects_service.dart';
import '../../services/audio/device_dsp.dart';
import '../../services/audio/media3/media3_playback_bridge.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/scrolling_page_chrome.dart';
import 'settings_widgets.dart';

part 'equalizer_page/page.dart';
part 'equalizer_page/band_slider.dart';
part 'equalizer_page/band_slider_vertical.dart';
part 'equalizer_page/band_track_painter.dart';
part 'equalizer_page/preset_chips.dart';
