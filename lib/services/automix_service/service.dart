part of '../automix_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AutomixService — offline, AI-free DJ-style auto-mixing.
//
// Layers (following the app's single-edge rule):
//
//   UI (settings: AutomixSection)
//     ↓
//   AutomixService           (this — feature cache, settings, plan → queue)
//     ↓                      ↓
//   AutomixEngine (pure)     MethodChannel 'musicplayer/automix'
//     ↓                      ↓ (Kotlin DSP: BPM onset-autocorrelation +
//   [AutomixPlan]             |    Krumhansl–Schmuckler chroma keys, energy)
//   AudioService.playSongAt  MediaExtractor/MediaCodec via PcmDecoder
//
// Native *owns* playback: the service only computes a deterministic order and
// hands a reordered list to AudioService.playSongAt — identical to how
// playlists reach the engine today. Crossfade is applied via the existing /
/// normal AudioEffectsService path so the treatment loads the same feedback
// paths as the manual crossfade picker.
// ═══════════════════════════════════════════════════════════════════════════════

class AutomixService {
  AutomixService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/automix');

  // ── Settings ───────────────────────────────────────────────────────────────

  static final ValueNotifier<AutomixSettings> settings = ValueNotifier(
    const AutomixSettings(),
  );

  static Future<void>? _settingsLoadFuture;

  /// Shares one in-flight load between startup, the settings UI and AutoMix.
  /// The completed Future is retained so late callers never race a partially
  /// restored configuration.
  static Future<void> loadSettings() =>
      _settingsLoadFuture ??= _loadSettings();

  static Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('automixSettings');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) settings.value = AutomixSettings.fromMap(map);
      }

      automixEnabled.value = prefs.getBool('automixEnabled') ?? true;

      final restored = prefs.getDouble('automixSavedCrossfade');
      if (restored != null && _savedCrossfade == null) {
        _savedCrossfade = restored;
        // automixActive is process-local. If the process was killed during a
        // mix, no active session can restore this override later, so recover
        // the user's saved crossfade immediately during startup.
        if (!automixActive.value) await _restoreCrossfade();
      }
    } on Object catch (e) {
      LogService.warn('Automix', 'loadSettings failed: $e');
    }
  }

  static Future<void> saveSettings(AutomixSettings value) async {
    settings.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('automixSettings', jsonEncode(value.toMap()));
    } on Object catch (e) {
      LogService.warn('Automix', 'saveSettings failed: $e');
    }
  }

  // ── Live state ─────────────────────────────────────────────────────────────

  /// Persisted master switch for AutoMix. The active queue session remains
  /// separately tracked by [automixActive].
  static final ValueNotifier<bool> automixEnabled = ValueNotifier(true);

  /// Whether the current playback session has AutoMix engaged and owns its
  /// temporary crossfade override.
  static final ValueNotifier<bool> automixActive = ValueNotifier(false);

  static bool _autoQueueListenerInstalled = false;
  static bool _autoMixPreparing = false;
  static bool _autoMixCheckRunning = false;
  static String? _lastAutoQueueIdentity;

  /// Automatically prepares upcoming tracks on a newly loaded queue.
  static void initializeAutoMix() {
    if (_autoQueueListenerInstalled) return;
    _autoQueueListenerInstalled = true;
    AudioService.playbackState.addListener(_onPlaybackStateForAutoMix);
  }

  static void _onPlaybackStateForAutoMix() {
    if (_autoMixCheckRunning || _autoMixPreparing) {
      return;
    }
    _autoMixCheckRunning = true;
    unawaited(_checkPlaybackStateForAutoMix());
  }

  static Future<void> _checkPlaybackStateForAutoMix() async {
    try {
      await loadSettings();
      if (!automixEnabled.value ||
          AudioEffectsService.bitPerfectMode.value ||
          _autoMixPreparing) {
        return;
      }
      final state = AudioService.playbackState.value;
      final queue = state.currentPlaylist;
      if (!state.isPlaying || state.currentSong == null || queue.length < 2 ||
          state.currentIndex < 0 || state.currentIndex >= queue.length) {
        return;
      }
      // Include the active item and queue length as well as the sorted IDs.
      // A newly loaded queue can contain the same library set but a different
      // starting track; that must refresh native deck targets without replacing
      // the currently playing item.
      final ids = queue.map((song) => song.id).toList()..sort();
      final identity =
          '${state.currentSong!.id}:${queue.length}:${state.shuffleEnabled}:${ids.join(',')}';
      if (_lastAutoQueueIdentity == identity) {
        return;
      }
      _lastAutoQueueIdentity = identity;
      await _prepareUpcomingTracks(queue, state.currentIndex);
    } finally {
      _autoMixCheckRunning = false;
    }
  }

  static double? _usableBpm(AutomixTrackFeatures features) {
    final bpm = features.bpm;
    if (bpm == null || !bpm.isFinite || bpm < 50 || bpm > 220 ||
        features.bpmConfidence < 0.35) return null;
    return bpm;
  }

  /// Builds conservative, pitch-preserving tempo targets for each upcoming deck.
  /// Corrections outside ±8% are avoided; uncertain tracks are left untouched.
  static List<Map<String, Object?>> _buildNativeTargets(
    AutomixTrackFeatures current,
    List<AutomixTrackFeatures> upcoming,
  ) {
    final currentBpm = _usableBpm(current);
    AutomixTrackFeatures? firstAnalyzed;
    for (final features in upcoming) {
      if (_usableBpm(features) != null) {
        firstAnalyzed = features;
        break;
      }
    }
    final reference = currentBpm ??
        (firstAnalyzed == null ? null : _usableBpm(firstAnalyzed));
    final referenceSongId = currentBpm != null
        ? current.songId
        : firstAnalyzed?.songId;

    final targets = <Map<String, Object?>>[];
    for (final features in <AutomixTrackFeatures>[current, ...upcoming]) {
      final sourceBpm = _usableBpm(features);
      var multiplier = 1.0;
      if (features.songId != current.songId &&
          reference != null &&
          sourceBpm != null &&
          features.songId != referenceSongId) {
        multiplier = (reference / sourceBpm).clamp(0.92, 1.08).toDouble();
      }
      targets.add(<String, Object?>{
        'id': features.songId,
        // Native beat-grid scheduling uses media-position time, so keep
        // the source BPM here; the independent multiplier controls output tempo.
        'bpm': ?sourceBpm,
        // Beat phase is more fragile than BPM. Only publish it when the
        // tempo estimate is strong and the phase is finite/non-negative;
        // otherwise native deliberately uses the ordinary time-based fade.
        if (sourceBpm != null &&
            features.bpmConfidence >= 0.45 &&
            features.beatOffsetMs != null &&
            features.beatOffsetMs!.isFinite &&
            features.beatOffsetMs! >= 0)
          'beatOffsetMs': features.beatOffsetMs,
        'multiplier': multiplier,
      });
    }
    return targets;
  }

  static Future<void> _prepareUpcomingTracks(List<LocalSong> queue, int currentIndex) async {
    if (_autoMixPreparing ||
        !automixEnabled.value ||
        AudioEffectsService.bitPerfectMode.value) {
      return;
    }
    final upcoming = queue.skip(currentIndex + 1).toList(growable: false);
    if (upcoming.isEmpty) {
      return;
    }
    _autoMixPreparing = true;
    try {
      await loadSettings();
      final currentSong = queue[currentIndex];
      // Use cached analyses only on the playback path: never decode full tracks
      // in the background while the current song is playing.
      final allFeatures = await featuresForAll([currentSong, ...upcoming]);
      if (!automixEnabled.value) {
        return;
      }
      final currentFeatures = allFeatures.first;
      // Keep the current song anchored at index 0 while letting its BPM/key
      // influence the first transition selected from the remaining tracks.
      final metrics = AutomixEngine.planSet(
        tracks: allFeatures, settings: settings.value, startIndex: 0,
      );
      if (metrics.order.length != upcoming.length + 1 || metrics.order.first != 0) {
        return;
      }
      // A native shuffle order must not be confused with the canonical queue
      // order. Keep the user's shuffle choice and still send per-track metadata
      // (targets are keyed by stable song ID); only reorder when shuffle is off.
      final latestState = AudioService.playbackState.value;
      if (latestState.currentSong?.id != currentSong.id ||
          latestState.currentIndex != currentIndex ||
          latestState.currentPlaylist.length != queue.length) {
        LogService.verbose('Automix', 'queue changed during planning; dropping stale plan');
        _lastAutoQueueIdentity = null;
        return;
      }
      final shuffleEnabled = latestState.shuffleEnabled;
      final upcomingIds = upcoming.map((song) => song.id).toList(growable: false);
      final hasUniqueIds = upcomingIds.toSet().length == upcomingIds.length;
      final canReorder = !shuffleEnabled && hasUniqueIds;
      final plannedIndices = canReorder
          ? metrics.order.skip(1).toList(growable: false)
          : List<int>.generate(upcoming.length, (index) => index + 1);
      final planned = [
        for (final index in plannedIndices) queue[currentIndex + index],
      ];
      final plannedFeatures = [
        for (final index in plannedIndices) allFeatures[index],
      ];

      if (canReorder) {
        // Reorder only upcoming items in one native transaction. Verify the
        // active song on both sides so stale plans cannot affect a newly
        // promoted deck or a queue that changed during analysis.
        final orderedTailIds = planned.map((song) => song.id).toList(growable: false);
        try {
          await AudioService.reorderUpcomingByIds(
            currentId: currentSong.id,
            orderedIds: orderedTailIds,
          );
        } on Object catch (e) {
          _lastAutoQueueIdentity = null;
          LogService.verbose('Automix', 'native queue changed during plan; retry later: $e');
          return;
        }
      } else {
        LogService.verbose(
          'Automix',
          shuffleEnabled
              ? 'shuffle is active; preserving native shuffle order and applying track metadata only'
              : 'duplicate song IDs in the queue tail; preserving queue order and applying track metadata only',
        );
      }

      if (automixEnabled.value) {
        final bpm = _usableBpm(currentFeatures);
        // Crossfade duration is expressed in media-timeline seconds. Manual
        // playback speed changes wall-clock duration, not the number of source
        // beats covered by the planned fade.
        final fadeSeconds = bpm == null
            ? metrics.crossfadeSeconds
            : (settings.value.crossfadeBeats * 60.0 / bpm)
                .clamp(2.0, 16.0)
                .toDouble();
        await _engageCrossfade(fadeSeconds);
        await AudioService.setAutomixTransition(
          enabled: true,
          targets: _buildNativeTargets(currentFeatures, plannedFeatures),
        );
        LogService.log(
          'Automix',
          'DJ plan prepared (${planned.length} upcoming tracks; '
              'beat/tempo matching ${bpm == null ? "fallback" : "enabled"}); '
              'current track preserved',
        );
      }
    } on Object catch (e, st) {
      LogService.warn('Automix', 'automatic queue preparation failed: $e');
      LogService.verbose('Automix', st.toString());
      _lastAutoQueueIdentity = null;
    } finally {
      _autoMixPreparing = false;
    }
  }

  static Future<void> setAutomixEnabled(bool enabled) async {
    automixEnabled.value = enabled;
    if (enabled) {
      _lastAutoQueueIdentity = null;
      _onPlaybackStateForAutoMix();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('automixEnabled', enabled);
    } on Object catch (e) {
      LogService.warn('Automix', 'save enabled state failed: $e');
    }
    if (!enabled) await disableAutomix();
  }

  static double? _savedCrossfade;

  // ── Feature cache ──────────────────────────────────────────────────────────

  // Bump whenever the native DSP feature semantics or feature serialization
  // changes. Old cache entries must never be interpreted as current analysis.
  static const int _analysisSchemaVersion = 3;
  static Future<void>? _analysisSchemaFuture;

  static final Map<int, AutomixTrackFeatures> _featuresCache = {};
  static final Map<int, String> _featuresIdentity = {};

  /// Offline file identity — size + mtime, so re-encoded or re-tagged files
  /// invalidate their cached analysis automatically.
  static String _identityForSong(LocalSong song) {
    // Web/browser builds have no dart:io identity; the caller gates on kIsWeb.
    try {
      final f = File(song.path);
      if (!f.existsSync()) return '';
      final st = f.statSync();
      return '${st.size}_${st.modified.millisecondsSinceEpoch}';
    } on Object {
      return '';
    }
  }

  static String _cacheKey(int songId) => 'automix_$songId';

  /// Invalidates the previous DSP cache generation once per process and resets
  /// the UI count, which otherwise would claim legacy (pre-fix) features were
  /// analyzed with the current extractor. Legacy per-track entries are left in
  /// place until each track is revisited, but version checks below make them a
  /// cache miss and the fresh analysis overwrites them.
  static Future<void> _ensureAnalysisSchemaVersion() =>
      _analysisSchemaFuture ??= _migrateAnalysisSchema();

  static Future<void> _migrateAnalysisSchema() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt('automix_analysisSchemaVersion');
      if (storedVersion != _analysisSchemaVersion) {
        _analyzedCount = 0;
        await prefs.setInt('automix_analyzedCount', 0);
        await prefs.setInt(
          'automix_analysisSchemaVersion',
          _analysisSchemaVersion,
        );
      }
    } on Object catch (e) {
      // Per-entry version checks still prevent stale cache reads if migration
      // persistence fails; log it so the count migration failure is visible.
      LogService.warn('Automix', 'analysis cache migration failed: $e');
    }
  }

  /// Cached analysis predates artist/title hydration in some installations.
  /// Always pair DSP data with the current MediaStore metadata before scoring.
  static AutomixTrackFeatures _withSongMetadata(
    AutomixTrackFeatures features,
    LocalSong song,
  ) => AutomixTrackFeatures(
    songId: features.songId,
    title: song.title,
    artist: song.artist,
    bpm: features.bpm,
    bpmConfidence: features.bpmConfidence,
    alternateBpm: features.alternateBpm,
    beatOffsetMs: features.beatOffsetMs,
    camelotNumber: features.camelotNumber,
    camelotMinor: features.camelotMinor,
    keyConfidence: features.keyConfidence,
    loudnessLufs: features.loudnessLufs,
    rmsDb: features.rmsDb,
    centroidHz: features.centroidHz,
    onsetRate: features.onsetRate,
  );

  /// Loaded (or freshly derived when nothing cached) features for [song].
  ///
  /// Fallback derivation is loudness-only (ReplayGain LUFS when available);
  /// BPM/key stay null so the engine treats them as neutral. Force a DSP
  /// analysis via the settings-page batch scan instead — keeping playback
  /// paths free of multi-second decode jobs.
  static Future<AutomixTrackFeatures> featuresFor(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) {
      return AutomixTrackFeatures(
        songId: song.id,
        title: song.title,
        artist: song.artist,
      );
    }

    await _ensureAnalysisSchemaVersion();
    final identity = _identityForSong(song);
    final inMemory = _featuresCache[song.id];
    if (inMemory != null && _featuresIdentity[song.id] == identity) {
      return _withSongMetadata(inMemory, song);
    }

    AutomixTrackFeatures? cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(song.id));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          final storedVersion = (map['version'] as num?)?.toInt();
          final storedIdentity = map['ident'] as String?;
          if (storedVersion == _analysisSchemaVersion &&
              identity.isNotEmpty &&
              storedIdentity == identity) {
            final data = map['data'] as Map? ?? const <String, dynamic>{};
            cached = _withSongMetadata(
              AutomixTrackFeatures.fromMap(data.cast<dynamic, dynamic>()),
              song,
            );
          }
        }
      }
    } on Object catch (e) {
      LogService.verbose('Automix', 'cache read failed for ${song.id}: $e');
    }

    final features = cached ?? (await _fallbackFeatures(song));
    if (identity.isNotEmpty) {
      _featuresCache[song.id] = features;
      _featuresIdentity[song.id] = identity;
    }
    return features;
  }

  static Future<AutomixTrackFeatures> _fallbackFeatures(LocalSong song) async {
    double? lufs;
    try {
      final loudness = await ReplayGainService.resolve(song);
      // LoudnessData carries the *recommended replay gain* (target − LUFS),
      // not an LUFS value itself. Invert it against the standard −18 LUFS
      // ReplayGain target so the engine's LUFS→energy mapping stays uniform.
      if (loudness.hasData) lufs = (-18.0 - loudness.gainDb).clamp(-24, -6).toDouble();
    } on Object catch (e) {
      LogService.verbose('Automix', 'loudness fallback failed: $e');
    }
    return AutomixTrackFeatures(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      loudnessLufs: lufs,
    );
  }

  /// Bulk feature resolution used by [startAutomix] (one SharedPreferences
  /// read batch instead of per-song awaits).
  static Future<List<AutomixTrackFeatures>> featuresForAll(
    List<LocalSong> songs,
  ) async {
    if (kIsWeb) {
      return [
        for (final s in songs)
          AutomixTrackFeatures(songId: s.id, title: s.title, artist: s.artist),
      ];
    }
    final out = <AutomixTrackFeatures>[];
    for (final song in songs) {
      out.add(await featuresFor(song));
    }
    return out;
  }

  // ── Plan → playback ────────────────────────────────────────────────────────

  /// Builds a new automix-ready queue from [playlist] (starting with
  /// [playlist[startIndex]]) and hands it to the playback engine.
  ///
  /// Returns the number of tracks sequenced, or -1 when the automix could not
  /// be applied (empty list / bit-perfect active).
  static Future<int> startAutomix(
    List<LocalSong> playlist,
    int startIndex,
  ) async {
    await loadSettings();
    if (!automixEnabled.value) return -1;
    if (playlist.isEmpty) return -1;
    if (AudioEffectsService.bitPerfectMode.value) {
      LogService.verbose(
        'Automix',
        'startAutomix rejected: Bit-Perfect mode disables crossfade',
      );
      return -1;
    }

    if (kIsWeb || playlist.length < 3) {
      // A straight shuffle of a tiny list beats a plan computed from nothing.
      LogService.verbose(
        'Automix',
        'startAutomix: not enough tracks (or web) — plain fallback',
      );
    }

    final features = await featuresForAll(playlist);
    final planMetrics = AutomixEngine.planSet(
      tracks: features,
      settings: settings.value,
      startIndex: startIndex,
    );
    final plan = planMetrics.order;
    if (plan.isEmpty) return -1;

    final sequenced = <LocalSong>[];
    for (final idx in plan) {
      sequenced.add(playlist[idx]);
    }

    LogService.log(
      'Automix',
      'Plan (${settings.value.profile.name}, ${sequenced.length} tracks, '
      'crossfade ${planMetrics.crossfadeSeconds.toStringAsFixed(1)}s, '
      'cost ${planMetrics.averageCost.toStringAsFixed(3)})',
    );

    final sequencedFeatures = [for (final index in plan) features[index]];
    final firstBpm = _usableBpm(sequencedFeatures.first);
    final fadeSeconds = firstBpm == null
        ? planMetrics.crossfadeSeconds
        : (settings.value.crossfadeBeats * 60.0 / firstBpm)
            .clamp(2.0, 16.0)
            .toDouble();
    await _engageCrossfade(fadeSeconds);
    await AudioService.setAutomixTransition(
      enabled: true,
      targets: _buildNativeTargets(
        sequencedFeatures.first,
        sequencedFeatures.skip(1).toList(growable: false),
      ),
    );
    await AudioService.playSongAt(
      playlist: sequenced,
      index: 0,
      autoplay: true,
    );
    return sequenced.length;
  }

  /// Restores the user's crossfade and drops the "engaged" flag.
  static Future<void> disableAutomix() async {
    automixActive.value = false;
    try {
      await AudioService.setAutomixTransition(
        enabled: false,
        targets: const <Map<String, Object?>>[],
      );
    } on Object catch (e) {
      LogService.warn('Automix', 'native transition reset failed: $e');
    }
    await _restoreCrossfade();
  }

  static Future<void> _engageCrossfade(double seconds) async {
    try {
      final current = AudioEffectsService.crossfadeDuration.value;
      final bitPerfect = AudioEffectsService.bitPerfectMode.value;
      if (!bitPerfect) {
        // Only snapshot the crossfade the first time the automix engages a
        // sessionId — repeated starts keep the original fallback so
        // disableAutomix always returns to the user's real preference.
        _savedCrossfade ??= current.toDouble();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('automixSavedCrossfade', _savedCrossfade!);
        await AudioEffectsService.setCrossfade(seconds);
      }
      automixActive.value = true;
    } on Object catch (e) {
      LogService.warn('Automix', 'crossfade engage failed: $e');
    }
  }

  static Future<void> _restoreCrossfade() async {
    final saved = _savedCrossfade;
    if (saved == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (AudioEffectsService.bitPerfectMode.value) {
        // While Bit-Perfect is on, update the persisted user value without
        // pushing DSP settings into the dedicated clean player. Also repair
        // its snapshot so turning Bit-Perfect off cannot resurrect the
        // temporary AutoMix crossfade instead of the user's preference.
        AudioEffectsService.crossfadeDuration.value = saved;
        await prefs.setDouble('crossfade', saved);
        if (prefs.getBool('bpmSnapValid') ?? false) {
          await prefs.setDouble('bpmSnapCrossfade', saved);
        }
      } else {
        await AudioEffectsService.setCrossfade(saved);
      }
      await prefs.remove('automixSavedCrossfade');
      _savedCrossfade = null;
    } on Object catch (e) {
      // Retain the in-memory value so a later disable/recovery can retry.
      LogService.warn('Automix', 'crossfade restore failed: $e');
    }
  }

  // ── Batch library analysis ────────────────────────────────────────────────

  static final ValueNotifier<AutomixAnalysisProgress> analysisProgress =
      ValueNotifier(const AutomixAnalysisProgress());

  static bool _analysisCancelled = false;
  static Future<void>? _analysisFuture;
  static int? _analyzedCount;
  static final Map<int, Future<AutomixTrackFeatures?>> _inFlight = {};

  /// Whether any song has had a full DSP analysis recorded already — used by
  /// the UI to motivate running the batch scan.
  static Future<bool> hasAnyAnalysis() async {
    await _loadAnalyzedCount();
    return (_analyzedCount ?? 0) > 0;
  }

  static Future<int> analyzedCount() async {
    await _loadAnalyzedCount();
    return _analyzedCount ?? 0;
  }

  static Future<void> _loadAnalyzedCount() async {
    await _ensureAnalysisSchemaVersion();
    if (_analyzedCount != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _analyzedCount = prefs.getInt('automix_analyzedCount');
    } on Object {
      _analyzedCount = null;
    }
  }

  static void _bumpAnalyzedCount(int delta) {
    _analyzedCount = (_analyzedCount ?? 0) + delta;
    unawaited(_persistAnalyzedCount());
  }

  static Future<void> _persistAnalyzedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('automix_analyzedCount', _analyzedCount ?? 0);
    } on Object catch (e) {
      LogService.warn('Automix', 'analyzedCount persist failed: $e');
    }
  }

  /// Runs the DSP analysis for ONE track, returning cached features when the
  /// file identity matches, else asking native to decode+analyze.
  ///
  /// Concurrent calls for the same song are de-duplicated: the first caller
  /// issues the native request, later callers share its result.
  static Future<AutomixTrackFeatures?> analyzeOne(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return null;

    final existing = _inFlight[song.id];
    if (existing != null) return existing;

    final identity = _identityForSong(song);
    final completer = Completer<AutomixTrackFeatures?>();
    _inFlight[song.id] = completer.future;

    unawaited(_runAnalysis(completer, song, identity));

    try {
      return await completer.future;
    } finally {
      // remove() hands back the stored Future — nothing awaits it here: the
      // awaiting caller already got it above.
      _inFlight.remove(song.id)?.ignore();
    }
  }

  /// Drives one analysis to completion and pushes the result (or null on any
  /// failure — callers treat null as "no DSP data available") into [completer].
  static Future<void> _runAnalysis(
    Completer<AutomixTrackFeatures?> completer,
    LocalSong song,
    String identity,
  ) async {
    try {
      completer.complete(await _analyzeOneUncached(song, identity));
    } on Object catch (e, st) {
      LogService.warn('Automix', 'analyzeOne failed: $e\n$st');
      completer.complete(null);
    }
  }

  static Future<AutomixTrackFeatures?> _analyzeOneUncached(
    LocalSong song,
    String identity,
  ) async {
    await _ensureAnalysisSchemaVersion();
    // 1. Already analyzed for this exact file?
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(song.id));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          final storedVersion = (map['version'] as num?)?.toInt();
          final storedIdentity = map['ident'] as String?;
          if (storedVersion == _analysisSchemaVersion &&
              identity.isNotEmpty &&
              storedIdentity == identity) {
            final data = map['data'] as Map? ?? const <String, dynamic>{};
            final f = _withSongMetadata(
              AutomixTrackFeatures.fromMap(data.cast<dynamic, dynamic>()),
              song,
            );
            _featuresCache[song.id] = f;
            _featuresIdentity[song.id] = identity;
            return f;
          }
        }
      }
    } on Object catch (e) {
      LogService.verbose('Automix', 'analyze cache read failed: $e');
    }

    // 2. Native DSP.
    Map<String, dynamic> res;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('analyze', {
        'path': song.path,
      });
      if (r == null || r['success'] != true) return null;
      res = r;
    } on PlatformException catch (e) {
      if (e.code == 'scan_busy') {
        LogService.verbose('Automix', 'analysis channel busy: ${song.path}');
      }
      return null;
    } on Exception catch (e) {
      LogService.warn('Automix', 'analyze failed: $e');
      return null;
    }

    final bpm = (res['bpm'] as num?)?.toDouble();
    final bpc = automixClamp01((res['bpmConfidence'] as num?)?.toDouble() ?? 0);
    final alt = (res['alternateBpm'] as num?)?.toDouble();
    final beatOffsetMs = (res['beatOffsetMs'] as num?)?.toDouble();
    final camN = (res['camelotNumber'] as num?)?.toInt();
    final camM = res['camelotMinor'] as bool?;
    final kConf = automixClamp01((res['keyConfidence'] as num?)?.toDouble() ?? 0);
    final rmsDb = (res['rmsDb'] as num?)?.toDouble();

    // The native extractor currently exports RMS rather than integrated LUFS.
    // Keep LUFS as an optional future native field, and fall back to cached
    // ReplayGain metadata only when PCM RMS is unavailable.
    final loudnessLufs = (res['lufs'] as num?)?.toDouble() ??
        (rmsDb == null ? (await _fallbackFeatures(song)).loudnessLufs : null);

    // Confidence gates — store null (neutral) when the extractor is unsure,
    // so the engine never sequences against a wild guess.
    final features = AutomixTrackFeatures(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      bpm: bpc >= 0.15 ? bpm : null,
      bpmConfidence: bpc >= 0.15 ? bpc : 0,
      alternateBpm: bpm != null && bpc >= 0.15 ? alt : null,
      beatOffsetMs: bpm != null && bpc >= 0.20 ? beatOffsetMs : null,
      camelotNumber: kConf >= 0.25 ? camN : null,
      camelotMinor: kConf >= 0.25 ? camM : null,
      keyConfidence: kConf >= 0.25 ? kConf : 0,
      rmsDb: rmsDb,
      centroidHz: (res['centroidHz'] as num?)?.toDouble(),
      onsetRate: (res['onsetRate'] as num?)?.toDouble(),
      loudnessLufs: loudnessLufs,
    );

    if (identity.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _cacheKey(song.id),
          jsonEncode(<String, dynamic>{
            'version': _analysisSchemaVersion,
            'ident': identity,
            'data': features.toMap(),
          }),
        );
      } on Object catch (e) {
        LogService.verbose('Automix', 'analyze cache write failed: $e');
      }
      _featuresCache[song.id] = features;
      _featuresIdentity[song.id] = identity;
      _bumpAnalyzedCount(1);
    }
    return features;
  }

  /// Batch analysis over the whole library. Runs serially (decode is CPU and
  /// disk heavy); the caller is responsible for gathering the [List<LocalSong>].
  static Future<void> analyzeLibrary(List<LocalSong> songs) async {
    await loadSettings();
    if (_analysisFuture != null) return; // already running
    _analysisCancelled = false;

    analysisProgress.value = AutomixAnalysisProgress(
      total: songs.length,
      running: true,
    );

    Future<void> run() async {
      var done = 0;
      var failed = 0;
      for (final song in songs) {
        if (_analysisCancelled) {
          analysisProgress.value = analysisProgress.value.copyWith(
            running: false,
            cancelled: true,
            currentTitle: '',
          );
          return;
        }
        analysisProgress.value = analysisProgress.value.copyWith(
          currentTitle: song.title,
        );
        final f = await analyzeOne(song);
        if (f == null) failed++;
        done++;
        analysisProgress.value = analysisProgress.value.copyWith(
          done: done,
          failed: failed,
        );
      }
      analysisProgress.value = analysisProgress.value.copyWith(
        running: false,
        cancelled: false,
        currentTitle: '',
      );
      LogService.log(
        'Automix',
        'library analysis done: ${done - failed} ok / $failed failed',
      );
    }

    _analysisFuture = run();
    try {
      await _analysisFuture;
    } finally {
      _analysisFuture = null;
    }
  }

  /// Cancels the current batch analysis (best-effort; the in-flight native
  /// call completes but the next song is not fetched).
  static void cancelAnalysis() {
    _analysisCancelled = true;
  }

  /// Tests / diagnostics only: clears all in-memory state.
  static void resetInMemoryState() {
    _featuresCache.clear();
    _featuresIdentity.clear();
    _analyzedCount = null;
    _savedCrossfade = null;
    automixActive.value = false;
    _settingsLoadFuture = null;
  }
}
