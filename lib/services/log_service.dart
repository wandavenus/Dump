// ── LogService library ────────────────────────────────────────────────────────
//
// Library entry point for the in-app logging subsystem.
// Declares all shared imports and includes the implementation via `part`.
//
// Public surface: [LogService] (all static); [LogEntry], [LogLevel].

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'log_service/level.dart';
part 'log_service/entry.dart';
part 'log_service/service.dart';
part 'log_service/native_log_bridge.dart';
