part of '../automix_service.dart';

/// Builds a stable signature for the transition currently being prepared.
///
/// Native looks up targets by song ID and only consumes the current/outgoing
/// deck and the next/incoming deck for the live transition. Sorting each map's
/// keys makes the signature independent of map insertion order. Capturing the
/// full payload (rather than a hand-picked subset) means new cue fields cannot
/// silently be omitted from change detection.
String automixNativePlanSignature(
  int currentSongId,
  double fadeSeconds,
  List<Map<String, Object?>> targets,
) {
  final immediateTargets = <Map<String, Object?>>[];

  for (final target in targets.take(2)) {
    final keys = target.keys.toList()..sort();
    final canonical = <String, Object?>{};
    for (final key in keys) {
      final value = target[key];
      // JSON cannot encode non-finite doubles. Preserve their distinction
      // without allowing malformed analysis data to abort transition setup.
      canonical[key] = value is double && !value.isFinite
          ? value.toString()
          : value;
    }
    immediateTargets.add(canonical);
  }

  return jsonEncode(<Object?>[
    currentSongId,
    fadeSeconds.toStringAsFixed(2),
    immediateTargets,
  ]);
}
