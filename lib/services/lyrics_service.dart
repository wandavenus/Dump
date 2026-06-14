import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyric_line.dart';
import 'audio/audio_effects_service.dart';
import 'log_service.dart';

part 'lyrics_service/source.dart';
part 'lyrics_service/result.dart';
part 'lyrics_service/service.dart';
