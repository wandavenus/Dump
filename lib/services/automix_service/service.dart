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

/// Exponential backoff for tracks whose DSP analysis failed or remained
/// incomplete. Retries continue at a capped interval instead of permanently
/// suppressing a file after one transient decoder/channel failure.
Duration automixAnalysisRetryDelay(int failedAttempts) {
  if (failedAttempts <= 0) return Duration.zero;
  final exponent = failedAttempts >= 6 ? 5 : failedAttempts - 1;
  final seconds = 30 * (1 << exponent);
  return Duration(seconds: seconds > 900 ? 900 : seconds);
}

class _AutomixAnalysisBusy implements Exception {
  const _AutomixAnalysisBusy();
}

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
  static Future<void> loadSettings() => _settingsLoadFuture ??= _loadSettings();

  static Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('automixSettings');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) settings.value = AutomixSettings.fromMap(map);
      }

      automixEnabled.value = prefs.getBool('automixEnabled') ?? false;

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
  static final ValueNotifier<bool> automixEnabled = ValueNotifier(false);

  /// Whether the current playback session has AutoMix engaged and owns its
  /// temporary crossfade override.
  static final ValueNotifier<bool> automixActive = ValueNotifier(false);

  static bool _autoQueueListenerInstalled = false;
  static bool _autoMixPreparing = false;
  static bool _autoMixCheckRunning = false;
  static String? _lastAutoQueueIdentity;

  /// Upcoming tracks AutoMix keeps warm in the DSP analysis cache — the decks
  /// about to be mixed, which is all the next transition reads.
  static const int _analysisLookahead = 4;

  /// Whole-queue planning cap. AutoMix sequences the whole remaining queue in
  /// one pass (the order the listener hears is decided once, like Apple Music's
  /// Automix); the cap only stops a "play all" of thousands of songs from
  /// turning that single pass into a visible stall. Past the cap the user's own
  /// order is preserved untouched.
  static const int _planHorizonCap = 250;

  /// Tracks at the head of a plan that get full features (cached DSP *or* the
  /// loudness fallback) instead of cached-only features. These are the decks
  /// whose cue is read on the very next fade.
  static const int _nearFeatureCount = 6;

  /// Deck targets pushed to native per plan: the playing deck plus the near
  /// window. Native keys targets by song id and only ever reads the pair in
  /// play, so shipping a 250-track plan would be pure channel traffic.
  static const int _targetHorizon = 4;

  /// Whole-set fade used when the outgoing track has no usable tempo at all —
  /// the same fallback the per-transition cue uses.
  static const double _fallbackFadeSeconds = 6.0;

  /// Decodes per analysis pass — small on purpose: the pipeline runs while
  /// music plays and must never compete with the audio decoder for long.
  static const int _analysisPerPass = 2;

  /// Delay before the pipeline resumes filling the cache for the same queue.
  static const Duration _analysisResumeDelay = Duration(seconds: 3);

  /// Signature of the deck plan currently pushed to Android (see
  /// [_nativePlanSignature]). Null means native holds no plan.
  static String? _lastNativeSignature;

  /// Tail order the last full plan pushed to native, excluding the track that
  /// was playing when it was built. While the live queue tail is a pure
  /// continuation of this list the plan still holds, so the next transition
  /// only refreshes deck targets instead of re-running the engine.
  static List<int>? _plannedTail;

  /// Set when fresh DSP analysis lands for the tracks about to mix: the existing
  /// order was decided with the data available then, so it is worth re-deciding
  /// once. The background library sweep deliberately does NOT set this — a
  /// 250-track re-plan every sweep session would be a visible hitch.
  static bool _planBasisStale = false;

  /// A (re)plan is due: the queue moved, fresh DSP data landed, or native
  /// rejected the previous reorder.
  static bool _replanRequested = false;

  static int _replanRetryCount = 0;
  static int _automixGeneration = 0;
  static const int _maxReplanRetries = 5;
  static Timer? _replanTimer;
  static Timer? _analyzeTimer;
  static bool _autoAnalyzeRunning = false;

  /// Songs the DSP extractor has analyzed successfully in this process, and
  /// songs it could not analyze (not retried until the next launch).
  static final Set<int> _dspReady = <int>{};
  static final Set<int> _dspUnavailable = <int>{};
  static final Map<int, String> _dspReadyIdentity = <int, String>{};
  static final Map<int, String> _dspUnavailableIdentity = <int, String>{};
  static final Map<int, int> _dspFailureAttempts = <int, int>{};
  static final Map<int, DateTime> _dspRetryAt = <int, DateTime>{};

  /// Automatically prepares upcoming tracks on a newly loaded queue and arms the
  /// idle library sweep.
  static void initializeAutoMix() {
    if (_autoQueueListenerInstalled) return;
    _autoQueueListenerInstalled = true;
    AudioService.playbackState.addListener(_onPlaybackStateForAutoMix);
    // With AutoMix off the app must not decode anything in the background, so
    // the sweep is only armed here when the user already turned it on.
    if (automixEnabled.value) {
      _scheduleLibrarySweep(const Duration(seconds: 20));
    }
  }

  static void _onPlaybackStateForAutoMix() {
    if (_autoMixPreparing || _autoMixCheckRunning) {
      // A pass is already running (analysis and/or planning). Flag a re-check so
      // a queue change during it is never swallowed.
      _replanRequested = true;
      return;
    }
    _autoMixCheckRunning = true;
    unawaited(_checkPlaybackStateForAutoMix());
  }

  /// Ids of the tracks after the playing one, in queue order.
  static List<int> _tailIdsOf(AudioPlaybackState state, List<LocalSong> queue) {
    final ids = <int>[];
    for (var i = state.currentIndex + 1; i < queue.length; i++) {
      ids.add(queue[i].id);
    }
    return ids;
  }

  /// Identity of the plan-sensitive part of the queue: the active track plus a
  /// fingerprint of the **whole** remaining tail.
  ///
  /// Fingerprinting the whole tail (instead of a bounded window) is what makes a
  /// single whole-queue plan safe: any edit anywhere behind the playing track
  /// changes the identity. The FNV-1a loop is cheaper than joining the old
  /// window's strings and never allocates a library-sized string.
  static String _autoMixQueueIdentity(
    AudioPlaybackState state,
    List<LocalSong> queue,
    List<int> tailIds,
  ) {
    final nextIndex = state.nextTrackIndex;
    final nextTrackId = nextIndex != null && nextIndex >= 0 && nextIndex < queue.length
        ? queue[nextIndex].id
        : -1;
    return '${state.currentSong?.id}:${queue.length}:${state.shuffleEnabled}'
        ':$nextTrackId:${automixQueueFingerprint(tailIds)}';
  }

  static Future<void> _checkPlaybackStateForAutoMix() async {
    try {
      await loadSettings();
      if (!automixEnabled.value || AudioEffectsService.bitPerfectMode.value) {
        _stopAutoAnalyzePipeline();
        return;
      }
      final state = AudioService.playbackState.value;
      final queue = state.currentPlaylist;
      if (!state.isPlaying ||
          state.currentSong == null ||
          queue.length < 2 ||
          state.currentIndex < 0 ||
          state.currentIndex >= queue.length) {
        return;
      }
      final tailIds = _tailIdsOf(state, queue);
      final identity = _autoMixQueueIdentity(state, queue, tailIds);
      if (_lastAutoQueueIdentity != identity) {
        _lastAutoQueueIdentity = identity;
        // Every change refreshes the deck targets for the pair about to mix, so
        // native always holds the next few transitions' cues. Only a real queue
        // edit (add / remove / reorder / skip) throws away the whole-queue plan
        // and forces a fresh sequencing pass: a plain track advance is already
        // covered by the plan.
        if (!automixPlanContinues(_plannedTail ?? const <int>[], tailIds)) {
          _plannedTail = null;
        }
        _replanRequested = true;
        _replanRetryCount = 0;
      }

      // 1. Give the tracks about to be mixed their offline analysis before
      //    planning against them. Bounded and resumable, so a large library
      //    fills progressively instead of blocking the first transition.
      final analyzed = await _autoAnalyzeUpcomingTracks(
        queue,
        state.currentIndex,
        identity,
      );
      if (analyzed) _planBasisStale = true;

      // 2. (Re)plan when the queue moved, when fresh DSP data landed, or after
      //    a native rejection. Otherwise there is nothing new to sequence.
      if (!_replanRequested && !analyzed) return;
      _replanRequested = false;
      await _prepareUpcomingTracks(queue, state.currentIndex);
    } finally {
      _autoMixCheckRunning = false;
      final retryScheduled = _replanTimer?.isActive ?? false;
      final needsAnotherPass = _replanRequested;
      // Consume the flag: a follow-up pass must be event-driven, never a loop.
      _replanRequested = false;
      if (retryScheduled) {
        // The bounded retry timer owns the next attempt.
      } else if (needsAnotherPass && automixEnabled.value) {
        // A queue change arrived while planning — settle it in a fresh pass.
        scheduleMicrotask(_onPlaybackStateForAutoMix);
      } else {
        _scheduleAnalysisResume();
      }
    }
  }

  static double? _usableBpm(AutomixTrackFeatures features) {
    final bpm = features.bpm;
    if (bpm == null ||
        !bpm.isFinite ||
        bpm < 50 ||
        bpm > 220 ||
        features.bpmConfidence < 0.35) {
      return null;
    }
    return bpm;
  }

  /// Practical tempo range for deck synchronization (BPM).
  static bool _tempoInRange(double? bpm) =>
      bpm != null && bpm.isFinite && bpm >= 50 && bpm <= 220;

  /// Builds the per-deck plan native needs.
  ///
  /// The outgoing deck publishes its **exit** grid (the blend happens at the
  /// end of that track), every incoming deck publishes its head grid, and each
  /// incoming track carries the tempo multiplier (±8 %, pitch-preserving) plus
  /// one transition cue: fade length, transfer curve and level match for the
  /// pair it actually follows in the mix order.
  ///
  /// Only *matchable* pairs are pulled together: a deck further than
  /// [automixTempoMatchTolerance] from the outgoing exit tempo keeps its own
  /// tempo and gets no beat grid, so native falls back to a clean equal-power
  /// crossfade instead of a stretched, wobbly blend.
  static List<Map<String, Object?>> _buildNativeTargets(
    AutomixTrackFeatures current,
    List<AutomixTrackFeatures> upcoming,
  ) {
    final ordered = <AutomixTrackFeatures>[current, ...upcoming];
    final exitBpm = automixExitBpm(current);
    final reference = _tempoInRange(exitBpm) && current.tailBpmConfidence >= 0.35
        ? exitBpm
        : null;

    final targets = <Map<String, Object?>>[];
    for (var i = 0; i < ordered.length; i++) {
      final features = ordered[i];
      final isOutgoing = i == 0;
      final bpm = isOutgoing ? exitBpm : features.bpm;
      final beatOffsetMs = isOutgoing
          ? features.tailBeatOffsetMs
          : features.beatOffsetMs;
      final downbeatOffsetMs = isOutgoing
          ? features.tailDownbeatOffsetMs
          : features.downbeatOffsetMs;
      final confidence = isOutgoing ? features.tailBpmConfidence : features.bpmConfidence;
      final confidentBpm = confidence >= 0.35 && _tempoInRange(bpm)
          ? bpm
          : null;

      // The outgoing deck is never pulled (referenceBpm: null), it only
      // publishes the grid the fade aligns to.
      final match = automixTempoMatch(
        referenceBpm: isOutgoing ? null : reference,
        trackBpm: confidentBpm,
      );
      final gridBpm = isOutgoing || match.$1 ? confidentBpm : null;

      final target = <String, Object?>{
        'id': features.songId,
        // Native beat-grid scheduling works in media-position time, so this is
        // the deck's own tempo; [multiplier] controls the output tempo.
        'bpm': ?gridBpm,
        // Beat phase is more fragile than BPM: publish it only when the tempo
        // estimate is strong and the phase is finite/non-negative, otherwise
        // native deliberately keeps the ordinary time-based fade.
        if (gridBpm != null &&
            confidence >= 0.35 &&
            beatOffsetMs != null &&
            beatOffsetMs.isFinite &&
            beatOffsetMs >= 0)
          'beatOffsetMs': beatOffsetMs,
        if (gridBpm != null &&
            confidence >= 0.35 &&
            downbeatOffsetMs != null &&
            downbeatOffsetMs.isFinite &&
            downbeatOffsetMs >= 0)
          'downbeatOffsetMs': downbeatOffsetMs,
        if (features.dropCueMs != null &&
            features.dropCueMs!.isFinite &&
            features.dropCueMs! >= 0)
          'dropCueMs': features.dropCueMs,
        'multiplier': isOutgoing ? 1.0 : match.$2,
      };

      if (!isOutgoing) {
        final previous = i == 1 ? current : ordered[i - 1];
        final cue = automixTransitionCue(
          outgoing: previous,
          incoming: features,
          settings: settings.value,
        );
        target['fadeSeconds'] = cue.fadeSeconds;
        target['fadeCurve'] = cue.curveGamma;
        target['levelTrimOutgoing'] = cue.outgoingTrim;
        target['levelTrimIncoming'] = cue.incomingTrim;
        target['transitionStrategy'] = cue.strategy.code;
        target['bassOverlapGainOutgoing'] = cue.outgoingBassOverlapGain;
        target['bassOverlapGainIncoming'] = cue.incomingBassOverlapGain;
        target['midOverlapGainOutgoing'] = cue.outgoingMidOverlapGain;
        target['midOverlapGainIncoming'] = cue.incomingMidOverlapGain;
        target['highOverlapGainOutgoing'] = cue.outgoingHighOverlapGain;
        target['highOverlapGainIncoming'] = cue.incomingHighOverlapGain;
      }
      targets.add(target);
    }
    return targets;
  }

  static Future<void> _prepareUpcomingTracks(
    List<LocalSong> queue,
    int currentIndex,
  ) async {
    final generation = _automixGeneration;
    if (_autoMixPreparing ||
        !automixEnabled.value ||
        AudioEffectsService.bitPerfectMode.value) {
      return;
    }
    if (currentIndex < 0 || currentIndex >= queue.length) return;
    final playbackSnapshot = AudioService.playbackState.value;
    if (playbackSnapshot.currentIndex != currentIndex ||
        playbackSnapshot.currentSong?.id != queue[currentIndex].id ||
        !automixQueueSnapshotMatches(
          queue.map((song) => song.id).toList(growable: false),
          playbackSnapshot.currentPlaylist.map((song) => song.id).toList(growable: false),
        )) {
      _scheduleReplanRetry();
      return;
    }
    final upcoming = automixUpcomingTracks<LocalSong>(
      queue,
      currentIndex,
      shuffleEnabled: playbackSnapshot.shuffleEnabled,
      nextTrackIndex: playbackSnapshot.nextTrackIndex,
    );
    if (upcoming.isEmpty) return;
    _autoMixPreparing = true;
    try {
      await loadSettings();
      final currentSong = queue[currentIndex];
      // Keep canonical queue order for plan continuation and native CAS, even
      // when Shuffle selects a non-linear next item for the next fade.
      final tailIds = _tailIdsOf(playbackSnapshot, queue);

      // ── Near window: what the next transition actually reads ──────────────
      // The playing deck plus the decks about to be mixed in. Those always get
      // full features (cached DSP, else the loudness fallback) because their cue
      // is used on the very next fade.
      final nearCount = math.min(_analysisLookahead + 1, upcoming.length);
      final nearFeatures = await featuresForAll(<LocalSong>[
        currentSong,
        ...upcoming.take(nearCount),
      ]);
      if (!_isAutoMixGenerationCurrent(generation)) {
        return;
      }
      // Validate again after awaits: Shuffle can pick another next item, or a
      // queue edit can land while the feature cache is loading.
      final postLoadState = AudioService.playbackState.value;
      if (postLoadState.currentSong?.id != currentSong.id ||
          postLoadState.currentIndex != currentIndex ||
          postLoadState.shuffleEnabled != playbackSnapshot.shuffleEnabled ||
          postLoadState.nextTrackIndex != playbackSnapshot.nextTrackIndex ||
          !automixQueueSnapshotMatches(
            queue.map((song) => song.id).toList(growable: false),
            postLoadState.currentPlaylist.map((song) => song.id).toList(growable: false),
          )) {
        LogService.verbose('Automix', 'playback queue changed during feature loading; dropping stale targets');
        _scheduleReplanRetry();
        return;
      }

      // Fresh analysis for the decks about to mix makes the current order worth
      // re-deciding once: the whole-queue plan was built with the data that
      // existed at the time.
      if (_planBasisStale) {
        _planBasisStale = false;
        _plannedTail = null;
      }

      // ── One plan for the whole remaining queue ────────────────────────────
      // A plain track advance leaves the plan valid, so only the deck targets
      // are refreshed; any real queue edit re-sequences everything.
      var currentFeatures = nearFeatures.first;
      var plannedFeatures = nearFeatures.skip(1).toList(growable: false);
      double? plannedCrossfadeSeconds;

      final preserveQueueOrder = playbackSnapshot.shuffleEnabled ||
          tailIds.toSet().length != tailIds.length;
      if (preserveQueueOrder) {
        // Shuffle owns its permutation, and duplicate IDs cannot be safely
        // permuted by the ID-based native queue API.
        _plannedTail = tailIds;
      } else if (!automixPlanContinues(_plannedTail ?? const <int>[], tailIds)) {
        // Sequence the ENTIRE remaining queue in a single pass (capped): the
        // order the listener hears is decided once, not re-decided before every
        // transition. Far tracks score from cached analysis only — resolving
        // loudness for hundreds of songs would stall the UI, and the engine is
        // built to treat missing features as neutral. The idle library sweep
        // fills that cache in the background, so plans sharpen over time.
        final horizon = math.min(_planHorizonCap, upcoming.length);
        final window = automixPlanWindow<LocalSong>(
          queue,
          currentIndex,
          horizon,
        );
        final allFeatures = await _featuresForPlan(window);
        if (!_isAutoMixGenerationCurrent(generation)) {
          return;
        }
        currentFeatures = allFeatures.first;
        // Keep the current song anchored at index 0 while letting its BPM/key
        // influence the first transition selected from the window.
        final metrics = AutomixEngine.planSet(
          tracks: allFeatures,
          settings: settings.value,
          startIndex: 0,
        );
        if (metrics.order.length != window.length || metrics.order.first != 0) {
          return;
        }
        plannedCrossfadeSeconds = metrics.crossfadeSeconds;
        // A native shuffle order must not be confused with the canonical queue
        // order. Keep the user's shuffle choice and still send per-track
        // metadata (targets are keyed by stable song ID); only reorder when
        // shuffle is off.
        if (!_isAutoMixGenerationCurrent(generation)) return;
        final latestState = AudioService.playbackState.value;
        if (latestState.currentSong?.id != currentSong.id ||
            latestState.currentIndex != currentIndex ||
            latestState.shuffleEnabled != playbackSnapshot.shuffleEnabled ||
            latestState.nextTrackIndex != playbackSnapshot.nextTrackIndex ||
            !automixQueueSnapshotMatches(
              queue.map((song) => song.id).toList(growable: false),
              latestState.currentPlaylist.map((song) => song.id).toList(growable: false),
            )) {
          LogService.verbose(
            'Automix',
            'queue changed during planning; dropping stale plan',
          );
          _scheduleReplanRetry();
          return;
        }
        final plannedIndices = metrics.order.skip(1).toList(growable: false);
        // Native only reads the pair in play, so publish the near part of the
        // new order; the following passes publish the rest as it arrives.
        plannedFeatures = <AutomixTrackFeatures>[
          for (final index in plannedIndices.take(_targetHorizon))
            allFeatures[index],
        ];

        final shuffleEnabled = latestState.shuffleEnabled;
        final hasUniqueIds = tailIds.toSet().length == tailIds.length;
        if (shuffleEnabled || !hasUniqueIds) {
          LogService.verbose(
            'Automix',
            shuffleEnabled
                ? 'shuffle is active; preserving native shuffle order and applying track metadata only'
                : 'duplicate song IDs in the queue tail; preserving queue order and applying track metadata only',
          );
          // The queue keeps its own order, so the plan is simply "the queue as
          // it is" — the next advance is still a continuation.
          _plannedTail = tailIds;
        } else {
          // Reorder the planned window in one native transaction; the untouched
          // remainder rides along unchanged so the native identity check (the
          // desired tail must be a permutation of the current tail) still holds.
          final orderedTailIds = automixOrderedTail<int>(
            <int>[for (final index in plannedIndices) window[index].id],
            tailIds,
            window.length - 1,
          );
          try {
            await AudioService.reorderUpcomingByIds(
              currentId: currentSong.id,
              expectedTailIds: tailIds,
              orderedIds: orderedTailIds,
            );
            if (!_isAutoMixGenerationCurrent(generation)) return;

            // The queue can change again while the native reorder Future is
            // completing. Do not publish targets for a sequence that is no
            // longer the live queue.
            final postReorderState = AudioService.playbackState.value;
            final expectedQueueAfterReorder = <int>[
              ...queue.take(currentIndex + 1).map((song) => song.id),
              ...orderedTailIds,
            ];
            if (postReorderState.currentSong?.id != currentSong.id ||
                postReorderState.currentIndex != currentIndex ||
                postReorderState.shuffleEnabled != playbackSnapshot.shuffleEnabled ||
                postReorderState.nextTrackIndex != playbackSnapshot.nextTrackIndex ||
                !automixQueueSnapshotMatches(
                  expectedQueueAfterReorder,
                  postReorderState.currentPlaylist.map((song) => song.id).toList(growable: false),
                )) {
              _scheduleReplanRetry();
              LogService.verbose(
                'Automix',
                'queue changed while native reorder completed; dropping transition targets',
              );
              return;
            }
            _plannedTail = orderedTailIds;
          } on Object catch (e) {
            // A rejected reorder must never strand the session on a stale plan.
            _scheduleReplanRetry();
            LogService.verbose(
              'Automix',
              'native queue changed during plan; retry later: $e',
            );
            return;
          }
        }
      }

      // Use the actual upcoming sequence if queue ordering is controlled by
      // native Shuffle or IDs are ambiguous. Never publish cues for another pair.
      if (preserveQueueOrder) {
        plannedFeatures = nearFeatures.skip(1).toList(growable: false);
        plannedCrossfadeSeconds = null;
      }

      if (_isAutoMixGenerationCurrent(generation)) {
        final bpm = _usableBpm(currentFeatures);
        // Crossfade duration is expressed in media-timeline seconds. Manual
        // playback speed changes wall-clock duration, not the number of source
        // beats covered by the planned fade.
        final fadeSeconds = bpm == null
            ? (plannedCrossfadeSeconds ?? _fallbackFadeSeconds)
            : (settings.value.crossfadeBeats * 60.0 / bpm)
                  .clamp(2.0, 16.0)
                  .toDouble();
        final targets = _buildNativeTargets(currentFeatures, plannedFeatures);
        final signature = _nativePlanSignature(
          currentSong.id,
          fadeSeconds,
          targets,
        );
        if (signature == _lastNativeSignature) {
          // Native already holds this exact deck plan (only the far end of the
          // window changed) — re-pushing it would rebuild the standby decoder.
          _replanRetryCount = 0;
          return;
        }
        await _engageCrossfade(fadeSeconds);
        if (!_isAutoMixGenerationCurrent(generation)) return;
        await AudioService.setAutomixTransition(
          enabled: true,
          targets: targets,
        );
        if (!_isAutoMixGenerationCurrent(generation)) return;
        _lastNativeSignature = signature;
        _replanRetryCount = 0;
        LogService.log(
          'Automix',
          'DJ plan ready (${plannedFeatures.length} deck targets of '
              '${tailIds.length} upcoming; beat/tempo matching '
              '${bpm == null ? "pending analysis" : "enabled"})',
        );
      }
    } on Object catch (e, st) {
      LogService.warn('Automix', 'automatic queue preparation failed: $e');
      LogService.verbose('Automix', st.toString());
      _scheduleReplanRetry();
    } finally {
      _autoMixPreparing = false;
    }
  }

  // ── Automatic DSP analysis pipeline ────────────────────────────────────────

  /// Fills the DSP cache for the tracks about to be mixed.
  ///
  /// This is what makes AutoMix automatic: like Apple Music's Automix the user
  /// never starts a scan — the pipeline analyzes the upcoming tracks while the
  /// current one plays, at most [_analysisPerPass] decodes per pass, and resumes
  /// after [_analysisResumeDelay] until the window is warm. [analyzeOne]
  /// persists each result by file identity, so a file is decoded once ever.
  ///
  /// Returns true when new analysis landed (the caller then re-plans, which is
  /// how the engine starts seeing real tempo/key data).
  static Future<bool> _autoAnalyzeUpcomingTracks(
    List<LocalSong> queue,
    int currentIndex,
    String identity,
  ) async {
    if (kIsWeb || _autoAnalyzeRunning || _analysisFuture != null) return false;
    final generation = _automixGeneration;
    if (!automixEnabled.value || AudioEffectsService.bitPerfectMode.value) {
      return false;
    }
    if (currentIndex < 0 || currentIndex >= queue.length) return false;

    bool needsAnalysis(LocalSong song) => _needsDspAnalysis(song);

    final analysisState = AudioService.playbackState.value;
    final candidateWindow = <LocalSong>[
      ...automixUpcomingTracks<LocalSong>(
        queue,
        currentIndex,
        shuffleEnabled: analysisState.shuffleEnabled,
        nextTrackIndex: analysisState.nextTrackIndex,
      ),
      ...automixPlanWindow<LocalSong>(queue, currentIndex, _analysisLookahead).skip(1),
    ];
    final candidates = <LocalSong>[];
    final seenCandidateIds = <int>{};
    for (final song in candidateWindow) {
      if (seenCandidateIds.add(song.id) && needsAnalysis(song)) candidates.add(song);
    }
    // The playing file is analyzed last: a second decoder pass over the file
    // ExoPlayer is reading right now must never delay the incoming track.
    final currentSong = queue[currentIndex];
    if (needsAnalysis(currentSong)) candidates.add(currentSong);
    if (candidates.isEmpty) return false;

    final batch = candidates.take(_analysisPerPass).toList(growable: false);
    _autoAnalyzeRunning = true;
    var analyzedAny = false;
    try {
      var done = 0;
      for (final song in batch) {
        if (!automixEnabled.value ||
            AudioEffectsService.bitPerfectMode.value ||
            _lastAutoQueueIdentity != identity) {
          break;
        }
        analysisProgress.value = analysisProgress.value.copyWith(
          running: true,
          done: done,
          total: batch.length,
          currentTitle: song.title,
        );
        final sourceIdentity = _identityForSong(song);
        AutomixTrackFeatures? features;
        try {
          features = await analyzeOne(song);
        } on _AutomixAnalysisBusy {
          // Queue saturation is temporary; the scheduled resume pass will retry.
          done++;
          continue;
        }
        if (!_isAutoMixGenerationCurrent(generation)) return false;
        if (features == null || !features.tailAnalyzed) {
          _markDspUnavailable(song, sourceIdentity);
        } else {
          _markDspReady(song, sourceIdentity);
        }
        if (features != null) analyzedAny = true;
        done++;
      }
      return analyzedAny;
    } finally {
      _autoAnalyzeRunning = false;
      analysisProgress.value = analysisProgress.value.copyWith(
        running: false,
        done: 0,
        total: 0,
        currentTitle: '',
      );
    }
  }

  /// Runs one more analysis pass shortly, so the window keeps filling while the
  /// current track plays. At most one pending pass at a time.
  static void _scheduleAnalysisResume() {
    if (kIsWeb || !automixEnabled.value) return;
    if (AudioEffectsService.bitPerfectMode.value) return;
    if (_autoAnalyzeRunning ||
        _analysisFuture != null ||
        (_analyzeTimer?.isActive ?? false)) {
      return;
    }
    final state = AudioService.playbackState.value;
    if (!state.isPlaying || state.currentSong == null) return;
    final queue = state.currentPlaylist;
    if (state.currentIndex < 0 || state.currentIndex >= queue.length) return;
    // Same priority order as the pass itself: upcoming tracks first, the
    // playing file last (mirrors _autoAnalyzeUpcomingTracks).
    final pendingWindow = <LocalSong>[
      ...automixUpcomingTracks<LocalSong>(
        queue,
        state.currentIndex,
        shuffleEnabled: state.shuffleEnabled,
        nextTrackIndex: state.nextTrackIndex,
      ),
      ...automixPlanWindow<LocalSong>(queue, state.currentIndex, _analysisLookahead).skip(1),
      queue[state.currentIndex],
    ];
    var pending = false;
    Duration? nextDelay;
    final now = DateTime.now();
    final seenPendingIds = <int>{};
    for (final song in pendingWindow) {
      if (!seenPendingIds.add(song.id)) continue;
      if (_needsDspAnalysis(song)) {
        pending = true;
        // Keep filling the cache promptly when there is work not in backoff.
        if (nextDelay == null ||
            _analysisResumeDelay.compareTo(nextDelay) < 0) {
          nextDelay = _analysisResumeDelay;
        }
        continue;
      }
      // Failed files are retried at their deadline. This prevents both a
      // permanent blacklist and a tight loop on files that cannot be decoded.
      final retryAt = _dspRetryAt[song.id];
      if (retryAt != null && retryAt.isAfter(now)) {
        pending = true;
        final remaining = retryAt.difference(now);
        if (nextDelay == null || remaining.compareTo(nextDelay) < 0) {
          nextDelay = remaining;
        }
      }
    }
    if (!pending) return;
    final delay = nextDelay ?? _analysisResumeDelay;
    _analyzeTimer = Timer(
      delay <= Duration.zero ? const Duration(milliseconds: 1) : delay,
      () {
        _analyzeTimer = null;
        if (automixEnabled.value) _onPlaybackStateForAutoMix();
      },
    );
  }

  static void _stopAutoAnalyzePipeline() {
    _analyzeTimer?.cancel();
    _analyzeTimer = null;
    if (analysisProgress.value.running) {
      analysisProgress.value = const AutomixAnalysisProgress();
    }
  }

  /// Retries a plan whose native reorder was rejected (normally because a
  /// crossfade was in flight). Bounded, so a permanently rejected plan cannot
  /// spin: after [_maxReplanRetries] AutoMix waits for real activity (queue
  /// change, track change, or the user toggling the switch) instead.
  static void _scheduleReplanRetry() {
    _replanTimer?.cancel();
    _replanTimer = null;
    if (_replanRetryCount >= _maxReplanRetries) {
      _replanRequested = false;
      return;
    }
    _replanRetryCount++;
    _replanRequested = true;
    _replanTimer = Timer(const Duration(milliseconds: 1500), () {
      _replanTimer = null;
      if (automixEnabled.value) _onPlaybackStateForAutoMix();
    });
  }

  /// Signature of the active deck pair sent to native.
  ///
  /// Include every field in both active targets: grid phases, structural cues,
  /// the pair-specific fade curve and level trims all affect native playback.
  /// Only these two decks affect the transition currently being prepared; the
  /// next playback-state update refreshes the signature for the following pair.
  static String _nativePlanSignature(
    int currentSongId,
    double fadeSeconds,
    List<Map<String, Object?>> targets,
  ) => automixNativePlanSignature(currentSongId, fadeSeconds, targets);

  static bool _isAutoMixGenerationCurrent(int generation) =>
      generation == _automixGeneration &&
      automixEnabled.value &&
      !AudioEffectsService.bitPerfectMode.value;

  static Future<void> setAutomixEnabled(bool enabled) async {
    final generation = ++_automixGeneration;
    automixEnabled.value = enabled;
    if (enabled) {
      _lastAutoQueueIdentity = null;
      _lastNativeSignature = null;
      _plannedTail = null;
      _planBasisStale = false;
      _replanRequested = true;
      _replanRetryCount = 0;
      _dspUnavailable.clear();
      _dspUnavailableIdentity.clear();
      _dspFailureAttempts.clear();
      _dspRetryAt.clear();
      _onPlaybackStateForAutoMix();
      _scheduleLibrarySweep(const Duration(seconds: 30));
    } else {
      await _disableAutomix(generation);
    }

    if (generation != _automixGeneration) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _automixGeneration) return;
      await prefs.setBool('automixEnabled', enabled);
    } on Object catch (e) {
      LogService.warn('Automix', 'save enabled state failed: $e');
    }
  }

  static double? _savedCrossfade;

  // ── Feature cache ──────────────────────────────────────────────────────────

  // Bump whenever the native DSP feature semantics or feature serialization
  // changes. Old cache entries must never be interpreted as current analysis.
  // v4: segmented head/middle/tail analysis (tempo/key votes, structure
  //     markers, exit beat grid) — v3 entries only described the first 300 s.
  // v5: add 16-beat phrase phase to intro/outro grids for phrase locking.
  // v6: retain structural cues and analyzed duration for cue-aware transitions.
  // v7: preserve native half/double-time alternate BPM and true source duration.
  // v9: persist vocal confidence and intro/tail structural-region metadata.
  // v11: add tailBpmConfidence to segment and track features.
  static const int _analysisSchemaVersion = 11;
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
      return '${f.absolute.path}_${st.size}_${st.modified.millisecondsSinceEpoch}';
    } on Object {
      return '';
    }
  }

  static String _cacheKey(int songId) => 'automix_$songId';

  /// Invalidate readiness and memory cache when a MediaStore ID points at a
  /// different on-disk file version. Persisted reads also validate this identity.
  static String _refreshDspStatusFor(LocalSong song) {
    final identity = _identityForSong(song);
    final id = song.id;
    if (_dspReady.contains(id) && _dspReadyIdentity[id] != identity) {
      _dspReady.remove(id);
      _dspReadyIdentity.remove(id);
    }
    if (_dspUnavailable.contains(id) && _dspUnavailableIdentity[id] != identity) {
      _dspUnavailable.remove(id);
      _dspUnavailableIdentity.remove(id);
      _dspFailureAttempts.remove(id);
      _dspRetryAt.remove(id);
    }
    if (_featuresIdentity.containsKey(id) && _featuresIdentity[id] != identity) {
      _featuresCache.remove(id);
      _featuresIdentity.remove(id);
    }
    return identity;
  }

  static bool _needsDspAnalysis(LocalSong song) {
    // Unseen tracks have no in-memory negative/positive status to invalidate;
    // their persisted cache is checked by analyzeOne when selected for work.
    // Avoid a synchronous stat for every item in a large library sweep.
    if (!_dspReady.contains(song.id) && !_dspUnavailable.contains(song.id)) {
      return true;
    }
    final identity = _refreshDspStatusFor(song);
    final ready = identity.isNotEmpty && _dspReady.contains(song.id) &&
        _dspReadyIdentity[song.id] == identity;
    final unavailable = _dspUnavailable.contains(song.id) &&
        _dspUnavailableIdentity[song.id] == identity;
    if (ready) return false;
    if (unavailable) {
      // A failed file is temporarily deferred, not blacklisted for the rest
      // of the process. The resume timer wakes when this deadline is reached.
      final retryAt = _dspRetryAt[song.id];
      return retryAt == null || !DateTime.now().isBefore(retryAt);
    }
    return true;
  }

  static void _markDspReady(LocalSong song, String identity) {
    if (identity.isEmpty) {
      _markDspUnavailable(song, identity);
      return;
    }
    _dspReady.add(song.id);
    _dspReadyIdentity[song.id] = identity;
    _dspUnavailable.remove(song.id);
    _dspUnavailableIdentity.remove(song.id);
    _dspFailureAttempts.remove(song.id);
    _dspRetryAt.remove(song.id);
  }

  static void _markDspUnavailable(LocalSong song, String identity) {
    _dspReady.remove(song.id);
    _dspReadyIdentity.remove(song.id);
    final sameSource = _dspUnavailable.contains(song.id) &&
        _dspUnavailableIdentity[song.id] == identity;
    final attempts = sameSource ? (_dspFailureAttempts[song.id] ?? 0) + 1 : 1;
    _dspUnavailable.add(song.id);
    _dspUnavailableIdentity[song.id] = identity;
    _dspFailureAttempts[song.id] = attempts;
    _dspRetryAt[song.id] = DateTime.now().add(
      automixAnalysisRetryDelay(attempts),
    );
  }

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
    downbeatOffsetMs: features.downbeatOffsetMs,
    tailDownbeatOffsetMs: features.tailDownbeatOffsetMs,
    dropCueMs: features.dropCueMs,
    tailBreakdownCueMs: features.tailBreakdownCueMs,
    dropConfidence: features.dropConfidence,
    tailBreakdownConfidence: features.tailBreakdownConfidence,
    structureRegion: features.structureRegion,
    structureConfidence: features.structureConfidence,
    tailStructureRegion: features.tailStructureRegion,
    tailStructureConfidence: features.tailStructureConfidence,
    vocalLikelihood: features.vocalLikelihood,
    vocalConfidence: features.vocalConfidence,
    durationSeconds: features.durationSeconds,
    camelotNumber: features.camelotNumber,
    camelotMinor: features.camelotMinor,
    keyConfidence: features.keyConfidence,
    loudnessLufs: features.loudnessLufs,
    rmsDb: features.rmsDb,
    centroidHz: features.centroidHz,
    onsetRate: features.onsetRate,
    // Keep all structural cues and both phrase/beat grids intact when cached
    // DSP data is paired with fresh MediaStore title/artist metadata.
    tailBpm: features.tailBpm,
    tailBpmConfidence: features.tailBpmConfidence,
    tailBeatOffsetMs: features.tailBeatOffsetMs,
    introRmsDb: features.introRmsDb,
    outroRmsDb: features.outroRmsDb,
    introEnergy: features.introEnergy,
    outroEnergy: features.outroEnergy,
    analyzedFraction: features.analyzedFraction,
    tailAnalyzed: features.tailAnalyzed,
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
    final identity = _refreshDspStatusFor(song);
    final inMemory = _featuresCache[song.id];
    if (inMemory != null && _featuresIdentity[song.id] == identity) {
      if (inMemory.tailAnalyzed) {
        _markDspReady(song, identity);
      } else {
        _dspReady.remove(song.id);
        _dspReadyIdentity.remove(song.id);
      }
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
            // Only complete tail analysis suppresses automatic re-analysis.
            if (cached.tailAnalyzed) _markDspReady(song, identity);
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
      if (loudness.hasData) {
        lufs = (-18.0 - loudness.gainDb).clamp(-24, -6).toDouble();
      }
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

  /// Features for a whole-queue plan.
  ///
  /// The first [_nearFeatureCount] tracks get the full treatment (cached DSP or
  /// the ReplayGain loudness fallback) because their cue drives the next fade;
  /// everything behind them is scored from the analysis cache and degrades to
  /// neutral metadata when nothing is cached yet. Resolving loudness for a whole
  /// library would turn one plan into a visible stall, and the engine treats a
  /// missing feature as neutral rather than as a reason to reject a track. The
  /// idle library sweep fills that cache in the background, so plans sharpen the
  /// longer the app runs — never by waiting for a decode.
  static Future<List<AutomixTrackFeatures>> _featuresForPlan(
    List<LocalSong> window,
  ) async {
    final out = <AutomixTrackFeatures>[];
    for (var i = 0; i < window.length; i++) {
      final song = window[i];
      out.add(
        i < _nearFeatureCount
            ? await featuresFor(song)
            : await _cachedOrNeutral(song),
      );
    }
    return out;
  }

  /// Cache-only features: the same DSP data [featuresFor] would return, but with
  /// no loudness side channel and no decode when nothing is cached.
  static Future<AutomixTrackFeatures> _cachedOrNeutral(LocalSong song) async {
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
            final features = _withSongMetadata(
              AutomixTrackFeatures.fromMap(data.cast<dynamic, dynamic>()),
              song,
            );
            _featuresCache[song.id] = features;
            _featuresIdentity[song.id] = identity;
            if (features.tailAnalyzed) {
              _markDspReady(song, identity);
            } else {
              _dspReady.remove(song.id);
              _dspReadyIdentity.remove(song.id);
            }
            return features;
          }
        }
      }
    } on Object catch (e) {
      LogService.verbose(
        'Automix',
        'plan cache read failed for ${song.id}: $e',
      );
    }
    return AutomixTrackFeatures(
      songId: song.id,
      title: song.title,
      artist: song.artist,
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
    final generation = _automixGeneration;
    await loadSettings();
    if (!_isAutoMixGenerationCurrent(generation)) return -1;
    if (playlist.isEmpty) return -1;
    if (AudioEffectsService.bitPerfectMode.value) {
      LogService.verbose(
        'Automix',
        'startAutomix rejected: Pure Playback disables crossfade',
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
    if (!_isAutoMixGenerationCurrent(generation)) return -1;
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
    // The whole playlist is already sequenced: record it as the live plan so the
    // automatic pipeline refreshes deck targets instead of sequencing the same
    // queue a second time, and ship only the near deck targets (native reads
    // them per song id anyway).
    _plannedTail = sequenced
        .map((song) => song.id)
        .skip(1)
        .toList(growable: false);
    await _engageCrossfade(fadeSeconds);
    if (!_isAutoMixGenerationCurrent(generation)) return -1;
    await AudioService.setAutomixTransition(
      enabled: true,
      targets: _buildNativeTargets(
        sequencedFeatures.first,
        sequencedFeatures.skip(1).take(_targetHorizon).toList(growable: false),
      ),
    );
    if (!_isAutoMixGenerationCurrent(generation)) return -1;
    await AudioService.playSongAt(
      playlist: sequenced,
      index: 0,
      autoplay: true,
    );
    return sequenced.length;
  }

  /// Restores the user's crossfade and drops the "engaged" flag.
  static Future<void> disableAutomix() async {
    final generation = ++_automixGeneration;
    automixEnabled.value = false;
    await _disableAutomix(generation);
  }

  static Future<void> _disableAutomix(int generation) async {
    automixActive.value = false;
    _lastAutoQueueIdentity = null;
    _lastNativeSignature = null;
    _plannedTail = null;
    _planBasisStale = false;
    _replanRequested = false;
    _replanRetryCount = 0;
    _replanTimer?.cancel();
    _replanTimer = null;
    _stopAutoAnalyzePipeline();
    _stopLibrarySweep();
    try {
      await AudioService.setAutomixTransition(
        enabled: false,
        targets: const <Map<String, Object?>>[],
      );
    } on Object catch (e) {
      LogService.warn('Automix', 'native transition reset failed: $e');
    }
    if (generation != _automixGeneration) return;
    await _restoreCrossfade();
  }

  static Future<void> _engageCrossfade(double seconds) async {
    final generation = _automixGeneration;
    try {
      final current = AudioEffectsService.crossfadeDuration.value;
      final bitPerfect = AudioEffectsService.bitPerfectMode.value;
      if (!bitPerfect) {
        // Only snapshot the crossfade the first time the automix engages a
        // sessionId — repeated starts keep the original fallback so
        // disableAutomix always returns to the user's real preference.
        _savedCrossfade ??= current.toDouble();
        final prefs = await SharedPreferences.getInstance();
        if (!_isAutoMixGenerationCurrent(generation)) return;
        await prefs.setDouble('automixSavedCrossfade', _savedCrossfade!);
        if (!_isAutoMixGenerationCurrent(generation)) return;
        await AudioEffectsService.setCrossfade(seconds);
        if (!_isAutoMixGenerationCurrent(generation)) return;
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
  static final Map<String, Future<AutomixTrackFeatures?>> _inFlight = {};

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

  /// Window length for one native analysis call. Bounded so a 90-minute file
  /// never needs a file-sized PCM buffer (the reason the old single-shot scan
  /// stopped at 300 s).
  static const double _segmentSeconds = 120.0;

  /// Above this length a middle window is added, so long tracks are sampled
  /// across their whole duration instead of only at the edges.
  static const double _veryLongFileSeconds = 480.0;

  /// Decodes one bounded window of [path] and returns its features plus the
  /// decoded file length. Returns null when the file cannot be analyzed
  /// (decoder failure, busy scanner).
  static Future<(AutomixSegmentFeatures, double)?> _analyzeWindow(
    String path,
    double startSeconds,
    double maxSeconds,
  ) async {
    Map<String, dynamic> res;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('analyze', {
        'path': path,
        'startSeconds': startSeconds,
        'maxSeconds': maxSeconds,
      });
      if (r == null || r['success'] != true) return null;
      res = r;
    } on PlatformException catch (e) {
      if (e.code == 'scan_busy') {
        LogService.verbose('Automix', 'analysis channel busy: $path');
        throw const _AutomixAnalysisBusy();
      }
      return null;
    } on Exception catch (e) {
      LogService.warn('Automix', 'analyze failed: $e');
      return null;
    }

    final segment = automixSegmentFeaturesFromAnalysisMap(
      res,
      fallbackStartSeconds: startSeconds,
      fallbackSeconds: maxSeconds,
    );
    final rawFileSeconds = (res['fileSeconds'] as num?)?.toDouble();
    final fileSeconds = rawFileSeconds != null &&
            rawFileSeconds.isFinite &&
            rawFileSeconds > 0
        ? rawFileSeconds
        : 0.0;
    return (segment, fileSeconds);
  }

  /// Head / middle / tail windows covering the whole file, ordered by position.
  ///
  /// Apple-Music-style analysis is not "the first N seconds": a six-minute
  /// track's outro tempo and level are what the transition actually needs, so
  /// the tail window is always analyzed for anything longer than one window,
  /// and the file length reported by native decides whether a middle window is
  /// worth the extra decode.
  static Future<(List<AutomixSegmentFeatures>, double, bool)> _analyzeSegments(
    LocalSong song,
  ) async {
    final head = await _analyzeWindow(song.path, 0, _segmentSeconds);
    if (head == null) return (const <AutomixSegmentFeatures>[], 0.0, false);
    final segments = <AutomixSegmentFeatures>[head.$1];
    final reportedDuration = head.$2;
    final mediaDuration = song.duration.inMilliseconds / 1000.0;
    var fileSeconds = 0.0;
    if (reportedDuration.isFinite && reportedDuration > 0) {
      fileSeconds = reportedDuration;
    } else if (mediaDuration.isFinite && mediaDuration > 0) {
      fileSeconds = mediaDuration;
    }

    // Anything shorter than one window is already covered completely.
    if (fileSeconds <= 0) {
      // Without a known duration we cannot prove that the head window covers
      // the file. Keep its useful features, but do not publish it as an exit
      // grid; a later launch can retry with fresh decoder metadata.
      return (segments, fileSeconds, false);
    }
    if (fileSeconds <= _segmentSeconds) {
      return (segments, fileSeconds, true);
    }

    var tailAnalyzed = false;
    final tailStart = fileSeconds - _segmentSeconds;
    if (tailStart > 0) {
      final tail = await _analyzeWindow(song.path, tailStart, _segmentSeconds);
      if (tail != null) {
        segments.add(tail.$1);
        tailAnalyzed = true;
      }
    }
    if (fileSeconds > _veryLongFileSeconds) {
      final midStart = fileSeconds / 2 - _segmentSeconds / 2;
      if (midStart > 0) {
        final mid = await _analyzeWindow(song.path, midStart, _segmentSeconds);
        if (mid != null) segments.add(mid.$1);
      }
    }
    segments.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return (segments, fileSeconds, tailAnalyzed);
  }

  /// Runs the DSP analysis for ONE track, returning cached features when the
  /// file identity matches, else asking native to decode+analyze.
  ///
  /// Concurrent calls for the same song are de-duplicated: the first caller
  /// issues the native request, later callers share its result.
  static Future<AutomixTrackFeatures?> analyzeOne(LocalSong song) async {
    if (kIsWeb || song.path.isEmpty) return null;

    final identity = _identityForSong(song);
    final flightKey = '${song.id}:${song.path}:$identity';
    final existing = _inFlight[flightKey];
    if (existing != null) return existing;

    final completer = Completer<AutomixTrackFeatures?>();
    _inFlight[flightKey] = completer.future;
    unawaited(_runAnalysis(completer, song, identity));

    try {
      return await completer.future;
    } finally {
      // Only evict this exact source version; an edit to the same MediaStore ID
      // may have started a separate analysis while the old decode was in flight.
      _inFlight.remove(flightKey)?.ignore();
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
    } on _AutomixAnalysisBusy catch (e, st) {
      completer.completeError(e, st);
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
            if (f.tailAnalyzed) {
              _featuresCache[song.id] = f;
              _featuresIdentity[song.id] = identity;
              _markDspReady(song, identity);
              return f;
            }
            // Partial cache entries remain useful through featuresFor(), but
            // analyzeOne() must retry them rather than treating them as done.
          }
        }
      }
    } on Object catch (e) {
      LogService.verbose('Automix', 'analyze cache read failed: $e');
    }

    // 2. Native DSP, in bounded windows that cover the whole file.
    final analysis = await _analyzeSegments(song);
    if (identity.isNotEmpty && _identityForSong(song) != identity) {
      LogService.verbose('Automix', 'source changed during DSP decode for ${song.id}; discarding stale features');
      return null;
    }
    final segments = analysis.$1;
    if (segments.isEmpty) return null;

    // The native extractor exports RMS rather than integrated LUFS; fall back
    // to cached ReplayGain metadata only when no window produced PCM RMS.
    final loudnessLufs = segments.any((s) => s.rmsDb != null)
        ? null
        : (await _fallbackFeatures(song)).loudnessLufs;

    // Merging applies the confidence gates (tempo vote agreement, key vote
    // share, per-window confidence) so the engine never sequences against a
    // wild guess.
    final features = automixMergeSegments(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      segments: segments,
      loudnessLufs: loudnessLufs,
      sourceDurationSeconds: analysis.$2,
      tailSegmentAnalyzed: analysis.$3,
    );
    if (identity.isNotEmpty && _identityForSong(song) != identity) {
      LogService.verbose('Automix', 'source changed before cache commit for ${song.id}; discarding stale features');
      return null;
    }

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
      if (features.tailAnalyzed) {
        _markDspReady(song, identity);
        _bumpAnalyzedCount(1);
      } else {
        _dspReady.remove(song.id);
        _dspReadyIdentity.remove(song.id);
        LogService.verbose(
          'Automix',
          'partial analysis cached for ${song.id}; exit window will be retried next launch',
        );
      }
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
        AutomixTrackFeatures? f;
        var busyRetries = 0;
        while (true) {
          try {
            f = await analyzeOne(song);
            break;
          } on _AutomixAnalysisBusy {
            if (_analysisCancelled || busyRetries >= 2) break;
            busyRetries++;
            await Future<void>.delayed(const Duration(milliseconds: 750));
          }
        }
        if (f == null || !f.tailAnalyzed) failed++;
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

  // ── Idle library sweep ─────────────────────────────────────────────────────
  //
  // Apple-Music-style analysis is invisible: AutoMix keeps sharpening its picture
  // of the library whenever the phone is idle enough for it. The sweep is
  // deliberately timid — a handful of tracks per session, one decode at a time, a
  // pause between decodes, and it stands down the moment the battery or the
  // thermal state says the phone would rather not.

  /// Tracks analyzed per sweep session before the sweep yields again.
  static const int _sweepBatchLimit = 40;

  /// Pause between two decodes inside a session: the sweep must never starve the
  /// decoder the current track is playing through.
  static const Duration _sweepPause = Duration(milliseconds: 350);

  /// Hand-out period between sweep sessions while work is pending.
  static const Duration _sweepInterval = Duration(minutes: 2);

  /// Retry period after the power/thermal state said no, or after a session was
  /// cut short.
  static const Duration _sweepRetryDelay = Duration(minutes: 3);

  /// Retry period once the whole library is analyzed — new files show up later.
  static const Duration _sweepIdleDelay = Duration(minutes: 30);

  /// Battery floor for an unplugged phone (see
  /// [DevicePowerState.allowsBackgroundAnalysis]).
  static const int _sweepMinBatteryPercent = 30;

  static Timer? _sweepTimer;
  static bool _sweepRunning = false;

  /// Arms (or re-arms) the idle sweep. Safe to call repeatedly.
  static void _scheduleLibrarySweep([Duration delay = _sweepInterval]) {
    if (kIsWeb) return;
    _sweepTimer?.cancel();
    _sweepTimer = Timer(delay, () {
      _sweepTimer = null;
      unawaited(_runLibrarySweepPass());
    });
  }

  static void _stopLibrarySweep() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    if (!_sweepRunning && analysisProgress.value.running) {
      // A sweep readout must not survive the feature being switched off; while a
      // sweep really is running it owns its own cleanup.
      analysisProgress.value = const AutomixAnalysisProgress();
    }
  }

  /// One sweep session: analyze at most [_sweepBatchLimit] tracks that have no
  /// cached analysis yet, re-checking the power state between decodes.
  ///
  /// Runs only in-process (the app has to be alive), which is what keeps it from
  /// needing a background-scheduling dependency: it simply uses the idle time a
  /// running player leaves behind.
  static Future<void> _runLibrarySweepPass() async {
    _sweepTimer = null;
    if (kIsWeb || !automixEnabled.value) return;
    // The transition pipeline owns the decoder whenever it is working.
    if (_sweepRunning ||
        _autoAnalyzeRunning ||
        _autoMixCheckRunning ||
        _analysisFuture != null) {
      _scheduleLibrarySweep(_sweepRetryDelay);
      return;
    }
    final songs = MediaStoreService.cachedSongs;
    if (songs == null || songs.isEmpty) {
      // No library loaded yet (or none at all): try again later instead of
      // walking MediaStore ourselves from a background timer.
      _scheduleLibrarySweep();
      return;
    }
    final power = await DeviceStateService.powerState();
    if (!power.allowsBackgroundAnalysis(
      minLevelPercent: _sweepMinBatteryPercent,
    )) {
      LogService.verbose(
        'Automix',
        'library sweep paused (${power.describe()})',
      );
      _scheduleLibrarySweep(_sweepRetryDelay);
      return;
    }
    final pending = <LocalSong>[
      for (final song in songs)
        if (song.path.isNotEmpty && _needsDspAnalysis(song)) song,
    ];
    if (pending.isEmpty) {
      _scheduleLibrarySweep(_sweepIdleDelay);
      return;
    }

    _sweepRunning = true;
    var analyzed = 0;
    try {
      final batch = pending.take(_sweepBatchLimit).toList(growable: false);
      for (final song in batch) {
        if (!automixEnabled.value) return;
        // Re-check between decodes: a phone that starts discharging, or heats
        // up, must stop the sweep immediately — not at the end of the batch.
        final now = await DeviceStateService.powerState();
        if (!now.allowsBackgroundAnalysis(
          minLevelPercent: _sweepMinBatteryPercent,
        )) {
          LogService.verbose(
            'Automix',
            'library sweep yielded (${now.describe()})',
          );
          break;
        }
        analysisProgress.value = AutomixAnalysisProgress(
          running: true,
          done: analyzed,
          total: batch.length,
          currentTitle: song.title,
        );
        final sourceIdentity = _identityForSong(song);
        AutomixTrackFeatures? features;
        try {
          features = await analyzeOne(song);
        } on _AutomixAnalysisBusy {
          LogService.verbose('Automix', 'library sweep yielded to a busy analysis queue');
          await Future<void>.delayed(_sweepPause);
          continue;
        }
        if (features == null || !features.tailAnalyzed) {
          _markDspUnavailable(song, sourceIdentity);
        } else {
          _markDspReady(song, sourceIdentity);
          analyzed++;
        }
        await Future<void>.delayed(_sweepPause);
      }
      LogService.log(
        'Automix',
        'library sweep: $analyzed analyzed, ${pending.length - analyzed} still pending',
      );
    } on Object catch (e) {
      LogService.warn('Automix', 'library sweep failed: $e');
    } finally {
      _sweepRunning = false;
      if (!_autoAnalyzeRunning && analysisProgress.value.running) {
        analysisProgress.value = const AutomixAnalysisProgress();
      }
      _scheduleLibrarySweep();
    }
  }

  /// Tests / diagnostics only: clears all in-memory state.
  static void resetInMemoryState() {
    _featuresCache.clear();
    _featuresIdentity.clear();
    _dspReady.clear();
    _dspUnavailable.clear();
    _dspReadyIdentity.clear();
    _dspUnavailableIdentity.clear();
    _dspFailureAttempts.clear();
    _dspRetryAt.clear();
    _analyzedCount = null;
    _savedCrossfade = null;
    automixActive.value = false;
    _lastAutoQueueIdentity = null;
    _lastNativeSignature = null;
    _plannedTail = null;
    _planBasisStale = false;
    _replanRequested = false;
    _replanRetryCount = 0;
    _replanTimer?.cancel();
    _replanTimer = null;
    _analyzeTimer?.cancel();
    _analyzeTimer = null;
    _stopLibrarySweep();
    _settingsLoadFuture = null;
  }
}
