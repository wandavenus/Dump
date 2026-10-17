part of '../automix_service.dart';

/// Native playback only consumes the active/outgoing deck and the immediate
/// incoming deck. Sending farther targets keyed by song ID lets a later repeat
/// of a song overwrite the live pair's tempo/phase/cue values in Media3 maps.
/// Rebuild the payload from the authoritative queue on every track advance.
/// A same-ID immediate pair cannot be represented safely by ID-keyed maps, so
/// omit AutoMix-specific cues for that pair and let ordinary crossfade run.
List<Map<String, Object?>> automixImmediateTransitionTargets(
  List<Map<String, Object?>> targets,
) {
  if (targets.length < 2) {
    return List<Map<String, Object?>>.unmodifiable(
      targets.map((target) => Map<String, Object?>.of(target)),
    );
  }
  if (targets[0]['id'] != null && targets[0]['id'] == targets[1]['id']) {
    return const <Map<String, Object?>>[];
  }
  return List<Map<String, Object?>>.unmodifiable(
    targets.take(2).map((target) => Map<String, Object?>.of(target)),
  );
}

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
