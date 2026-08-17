// ── ReplayGainService library ─────────────────────────────────────────────────
//
// This file is the library entry point for the ReplayGain subsystem.
// It declares all shared imports and includes the implementation via `part`.
//
// Why a separate entry-point file?
//   The implementation in `replay_gain_service/service.dart` is large (~450 lines)
//   and references multiple packages and local models.  Keeping the import block
//   here lets the part file stay focused on logic rather than dependency
//   management, and makes it easy to add future sub-parts (e.g. a scanner
//   result model) without touching the implementation file.
//
// Public surface: [ReplayGainService] (all static, accessed by PlaybackManager).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../models/local_song.dart';
import '../models/loudness_data.dart';
import 'log_service.dart';

part 'replay_gain_service/service.dart';
part 'replay_gain_service/models.dart';

/// File identity used to prevent a cached or scanned value from being applied
/// to a newer file at the same MediaStore id.
@immutable
class _ReplayGainFileIdentity {
  const _ReplayGainFileIdentity(this.path, this.size, this.mtimeMs);

  final String path;
  final int size;
  final int mtimeMs;

  @override
  bool operator ==(Object other) =>
      other is _ReplayGainFileIdentity &&
      other.path == path &&
      other.size == size &&
      other.mtimeMs == mtimeMs;

  @override
  int get hashCode => Object.hash(path, size, mtimeMs);
}
