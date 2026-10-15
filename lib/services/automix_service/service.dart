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

  /// Whether the last-started automix runover is still "engaged" — that is,
  /// the user-set crossfade is currently overridden by the plan and will be
  /// restored when [disableAutomix] runs.
  static final ValueNotifier<bool> automixActive = ValueNotifier(false);

  static double? _savedCrossfade;

  // ── Feature cache ──────────────────────────────────────────────────────────

  // Bump whenever the native DSP feature semantics or feature serialization
  // changes. Old cache entries must never be interpreted as current analysis.
  static const int _analysisSchemaVersion = 2;
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

    await _engageCrossfade(planMetrics.crossfadeSeconds);
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
