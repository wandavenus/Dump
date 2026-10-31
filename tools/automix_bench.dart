// AutoMix analysis benchmark / regression harness.
//
// Runs the native AutoMix analyzer over a manifest of labeled cases and reports
// tempo, key, metre and timing metrics. Cases are either deterministic
// synthetic signals generated in-memory (no audio files in the repo) or PCM
// WAV files supplied by the user.
//
// Usage (from the repository root):
//   dart run tools/automix_bench.dart
//   dart run tools/automix_bench.dart --check
//   dart run tools/automix_bench.dart --write-golden
//   dart run tools/automix_bench.dart --json
//   dart run tools/automix_bench.dart --filter 128
//
// The golden file records the current analyzer output for every case. `--check`
// re-runs the manifest and fails when a field moves outside its tolerance. It is
// a regression gate for algorithm changes, not a claim of perceptual accuracy:
// real-music accuracy is only meaningful once the manifest points at labeled
// WAVs.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:native_audio_runtime/native_audio_runtime.dart';

const String _defaultManifest = 'testdata/automix/manifest.json';
const String _defaultGolden = 'testdata/automix/golden.json';
const double _twoPi = 2.0 * math.pi;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }
  final manifestFile = File(options.manifest);
  if (!manifestFile.existsSync()) {
    stderr.writeln('manifest not found: ${options.manifest}');
    exitCode = 2;
    return;
  }
  final manifest =
      jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final cases = (manifest['cases'] as List? ?? const <Object?>[])
      .whereType<Map<String, dynamic>>()
      .map(_Case.fromJson)
      .where(
        (item) => options.filter == null || item.id.contains(options.filter!),
      )
      .toList(growable: false);
  if (cases.isEmpty) {
    stderr.writeln('no cases selected');
    exitCode = 2;
    return;
  }

  final results = <_Result>[];
  for (final item in cases) {
    final pcm = _loadCase(item, manifestFile.parent);
    if (pcm == null) {
      stderr.writeln('${item.id}: PCM unavailable, skipped');
      continue;
    }
    final sw = Stopwatch()..start();
    final analysis = NativeAutomix.analyze(pcm.samples, pcm.sampleRate);
    sw.stop();
    if (analysis == null) {
      stderr.writeln('${item.id}: analyzer rejected the PCM');
      exitCode = 1;
      continue;
    }
    results.add(
      _Result(
        testCase: item,
        analysis: analysis,
        elapsedMs: sw.elapsedMilliseconds,
        rssBytes: ProcessInfo.currentRss,
      ),
    );
  }
  if (results.isEmpty) {
    stderr.writeln('no analyzable cases');
    exitCode = 1;
    return;
  }

  if (options.writeGolden) {
    final golden = <String, dynamic>{
      'version': 1,
      'generatedBy': 'tools/automix_bench.dart',
      'cases': <String, dynamic>{
        for (final result in results)
          result.testCase.id: <String, dynamic>{
            'analysis': _snapshot(result.analysis),
            'elapsedMs': result.elapsedMs,
            'rssBytes': result.rssBytes,
          },
      },
    };
    await File(options.golden).parent.create(recursive: true);
    await File(
      options.golden,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(golden)}\n');
    stdout.writeln('wrote ${options.golden} (${results.length} cases)');
  }

  if (options.json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'summary': _summary(results),
        'cases': [for (final result in results) result.toJson()],
      }),
    );
  } else {
    _printTable(results);
  }

  if (options.check) {
    final goldenFile = File(options.golden);
    if (!goldenFile.existsSync()) {
      stderr.writeln('golden not found: ${options.golden}');
      exitCode = 2;
      return;
    }
    final golden =
        jsonDecode(await goldenFile.readAsString()) as Map<String, dynamic>;
    final failures = _checkGolden(
      results,
      (golden['cases'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    if (failures.isEmpty) {
      stdout.writeln('golden check passed (${results.length} cases)');
    } else {
      for (final failure in failures) {
        stderr.writeln('GOLDEN FAIL $failure');
      }
      stderr.writeln('golden check failed (${failures.length} fields)');
      exitCode = 1;
    }
  }
}

const String _usage =
    '''
AutoMix benchmark harness

Options:
  --manifest PATH   manifest JSON (default: $_defaultManifest)
  --golden PATH     golden JSON (default: $_defaultGolden)
  --write-golden    overwrite the golden file with current results
  --check           compare results against the golden file and exit 1 on drift
  --json            print machine-readable results
  --filter TEXT     only run case ids containing TEXT
  -h, --help        show this help
''';

class _Options {
  const _Options({
    required this.manifest,
    required this.golden,
    required this.writeGolden,
    required this.check,
    required this.json,
    required this.filter,
    required this.help,
  });

  final String manifest;
  final String golden;
  final bool writeGolden;
  final bool check;
  final bool json;
  final String? filter;
  final bool help;

  static _Options parse(List<String> args) {
    var manifest = _defaultManifest;
    var golden = _defaultGolden;
    var writeGolden = false;
    var check = false;
    var json = false;
    String? filter;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--manifest':
          if (++i < args.length) manifest = args[i];
        case '--golden':
          if (++i < args.length) golden = args[i];
        case '--write-golden':
          writeGolden = true;
        case '--check':
          check = true;
        case '--json':
          json = true;
        case '--filter':
          if (++i < args.length) filter = args[i];
        case '-h':
        case '--help':
          help = true;
        default:
          stderr.writeln('unknown argument: ${args[i]}');
          help = true;
      }
    }
    return _Options(
      manifest: manifest,
      golden: golden,
      writeGolden: writeGolden,
      check: check,
      json: json,
      filter: filter,
      help: help,
    );
  }
}

class _Case {
  const _Case({
    required this.id,
    required this.kind,
    required this.seconds,
    required this.sampleRate,
    this.file,
    this.bpm,
    this.meter = 4,
    this.tonic,
    this.minor = false,
    this.seed = 1,
    this.expect = const <String, dynamic>{},
  });

  final String id;
  final String kind;
  final double seconds;
  final int sampleRate;
  final String? file;
  final double? bpm;
  final int meter;
  final int? tonic;
  final bool minor;
  final int seed;
  final Map<String, dynamic> expect;

  factory _Case.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) => value is num ? value.toDouble() : null;
    int integer(Object? value, int fallback) {
      if (value is! num || !value.isFinite) return fallback;
      return value.toInt();
    }

    return _Case(
      id: json['id'] as String? ?? 'unnamed',
      kind:
          json['kind'] as String? ?? (json['file'] != null ? 'file' : 'click'),
      seconds: number(json['seconds']) ?? 45.0,
      sampleRate: integer(json['sampleRate'], 22050),
      file: json['file'] as String?,
      bpm: number(json['bpm']),
      meter: integer(json['meter'], 4),
      tonic: json['tonic'] == null ? null : integer(json['tonic'], 0),
      minor: json['minor'] as bool? ?? false,
      seed: integer(json['seed'], 1),
      expect:
          (json['expect'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

class _Pcm {
  _Pcm(this.samples, this.sampleRate, this.durationSeconds);

  final Float32List samples;
  final int sampleRate;
  final double durationSeconds;
}

_Pcm? _loadCase(_Case item, Directory manifestDir) {
  if (item.file != null) {
    final file = File(
      File(item.file!).isAbsolute
          ? item.file!
          : '${manifestDir.path}/${item.file!}',
    );
    if (!file.existsSync()) {
      stderr.writeln('${item.id}: WAV not found: ${file.path}');
      return null;
    }
    try {
      return _readWav(file);
    } on Object catch (error) {
      stderr.writeln('${item.id}: WAV decode failed: $error');
      return null;
    }
  }
  return _synthesize(item);
}

_Pcm? _synthesize(_Case item) {
  final rate = item.sampleRate;
  if (rate < 8000 || rate > 192000) return null;
  final seconds = item.seconds.clamp(1.0, 900.0).toDouble();
  final count = (seconds * rate).round();
  final out = Float32List(count);
  final random = math.Random(item.seed);
  final bpm = item.bpm;

  switch (item.kind) {
    case 'silence':
      return _Pcm(out, rate, seconds);
    case 'noise':
      for (var i = 0; i < count; i++) {
        out[i] = (random.nextDouble() * 2.0 - 1.0) * 0.15;
      }
      return _Pcm(out, rate, seconds);
    case 'tone':
      _addChordProgression(out, rate, item.tonic ?? 0, item.minor);
      _normalize(out, 0.5);
      return _Pcm(out, rate, seconds);
    case 'click':
      if (bpm == null || bpm <= 0) return null;
      _addChordProgression(out, rate, item.tonic ?? 0, item.minor, level: 0.10);
      _addClickTrain(
        out,
        rate,
        bpm: bpm,
        meter: item.meter.clamp(2, 6).toInt(),
        random: random,
      );
      _normalize(out, 0.89);
      return _Pcm(out, rate, seconds);
    case 'file':
      return null;
    default:
      stderr.writeln('${item.id}: unknown kind "${item.kind}"');
      return null;
  }
}

void _addChordProgression(
  Float32List out,
  int rate,
  int tonic,
  bool minor, {
  double level = 0.16,
}) {
  // I-V-vi-IV for major, i-VI-III-VII for natural minor. Both progressions
  // repeat every 8 s, long enough for the chroma vote to see the tonic in a
  // stable harmonic context.
  final majorIntervals = <List<int>>[
    [0, 4, 7],
    [7, 11, 14],
    [9, 12, 16],
    [5, 9, 12],
  ];
  final minorIntervals = <List<int>>[
    [0, 3, 7],
    [8, 12, 15],
    [3, 7, 10],
    [10, 14, 17],
  ];
  final chords = minor ? minorIntervals : majorIntervals;
  final rootHz = 261.625565 * math.pow(2.0, tonic / 12.0);
  final chordSeconds = 2.0;
  final totalSamples = out.length;
  final chordSamples = (chordSeconds * rate).round();
  for (var start = 0; start < totalSamples; start += chordSamples) {
    final chord = chords[(start ~/ chordSamples) % chords.length];
    final end = math.min(totalSamples, start + chordSamples);
    for (var i = start; i < end; i++) {
      final t = (i - start) / rate;
      final envelope = math.min(
        1.0,
        math.min(t / 0.03, (end - i) / rate / 0.03),
      );
      var value = 0.0;
      for (final semitone in chord) {
        final hz = rootHz * math.pow(2.0, semitone / 12.0);
        value += math.sin(_twoPi * hz * t);
      }
      // A soft sub-octave root anchors the key without dominating the click.
      value += 0.45 * math.sin(_twoPi * rootHz * 0.5 * t);
      out[i] += level * envelope * value / chord.length;
    }
  }
}

void _addClickTrain(
  Float32List out,
  int rate, {
  required double bpm,
  required int meter,
  required math.Random random,
}) {
  final beatSamples = 60.0 / bpm * rate;
  final clicks = (out.length / beatSamples).ceil();
  for (var beat = 0; beat < clicks; beat++) {
    final start = (beat * beatSamples).round();
    if (start >= out.length) break;
    final downbeat = beat % meter == 0;
    // Kick: fast downward pitch sweep with an exponential decay.
    final kickSamples = (0.10 * rate).round();
    for (var i = 0; i < kickSamples && start + i < out.length; i++) {
      final t = i / rate;
      final envelope = math.exp(-t * 38.0);
      final phase = _twoPi * (52.0 * t - 18.0 * t * t);
      out[start + i] += (downbeat ? 0.80 : 0.58) * envelope * math.sin(phase);
    }
    // Downbeat accent: short broadband click plus a higher body, so the
    // metre hypothesis has a bar-level accent rather than a flat pulse.
    if (downbeat) {
      final accentSamples = (0.035 * rate).round();
      for (var i = 0; i < accentSamples && start + i < out.length; i++) {
        final t = i / rate;
        final envelope = math.exp(-t * 90.0);
        out[start + i] += 0.22 * envelope * (random.nextDouble() * 2.0 - 1.0);
        out[start + i] += 0.18 * envelope * math.sin(_twoPi * 1800.0 * t);
      }
    }
    // A quiet offbeat hat keeps the texture realistic without competing with
    // the kick for the metrical level.
    final offbeat = (start + beatSamples * 0.5).round();
    final hatSamples = (0.018 * rate).round();
    for (var i = 0; i < hatSamples && offbeat + i < out.length; i++) {
      final t = i / rate;
      out[offbeat + i] +=
          0.035 * math.exp(-t * 180.0) * (random.nextDouble() * 2.0 - 1.0);
    }
  }
}

void _normalize(Float32List samples, double peak) {
  var maximum = 0.0;
  for (final value in samples) {
    final magnitude = value.abs();
    if (magnitude > maximum) maximum = magnitude;
  }
  if (maximum <= 1e-9) return;
  final gain = peak / maximum;
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
}

_Pcm _readWav(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  var offset = 12;
  int? format;
  int? channels;
  int? sampleRate;
  int? bits;
  int? dataOffset;
  int? dataLength;
  final data = ByteData.sublistView(bytes);
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final length = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = math.min(length, bytes.length - body);
      break;
    }
    offset = body + length + (length & 1);
  }
  if (format == null ||
      channels == null ||
      sampleRate == null ||
      bits == null ||
      dataOffset == null ||
      dataLength == null) {
    throw const FormatException('missing fmt/data chunk');
  }
  if (format != 1 && format != 3) {
    throw FormatException(
      'unsupported WAV format $format (PCM16/float32 only)',
    );
  }
  if (sampleRate < 8000 || sampleRate > 192000) {
    throw FormatException('unsupported WAV sample rate $sampleRate');
  }
  final bytesPerSample = bits ~/ 8;
  if (bytesPerSample != 2 && bytesPerSample != 4) {
    throw FormatException('unsupported WAV bit depth $bits');
  }
  final frameBytes = bytesPerSample * channels;
  final frames = dataLength ~/ frameBytes;
  final mono = Float32List(frames);
  var cursor = dataOffset;
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      if (format == 3) {
        sum += data.getFloat32(cursor, Endian.little);
      } else if (bits == 16) {
        sum += data.getInt16(cursor, Endian.little) / 32768.0;
      } else {
        sum += data.getInt32(cursor, Endian.little) / 2147483648.0;
      }
      cursor += bytesPerSample;
    }
    mono[frame] = sum / channels;
  }
  return _Pcm(mono, sampleRate, frames / sampleRate);
}

class _Result {
  const _Result({
    required this.testCase,
    required this.analysis,
    required this.elapsedMs,
    required this.rssBytes,
  });

  final _Case testCase;
  final NativeAutomixAnalysis analysis;
  final int elapsedMs;
  final int rssBytes;

  double? get expectedBpm => _number(testCase.expect['bpm']) ?? testCase.bpm;
  int? get expectedTonic => _integer(testCase.expect['tonic']);
  bool? get expectedMinor => testCase.expect['minor'] as bool?;
  int? get expectedMeter => _integer(testCase.expect['meter']);

  double? get bpmErrorPercent {
    final expected = expectedBpm;
    final measured = analysis.bpm;
    if (expected == null || expected <= 0 || measured == null) return null;
    return (measured - expected).abs() / expected * 100.0;
  }

  double? get bpmFoldedErrorPercent {
    final expected = expectedBpm;
    final measured = analysis.bpm;
    if (expected == null || expected <= 0 || measured == null) return null;
    var folded = measured;
    while (folded < expected * 0.75) {
      folded *= 2.0;
    }
    while (folded > expected * 1.5) {
      folded /= 2.0;
    }
    return (folded - expected).abs() / expected * 100.0;
  }

  bool? get octaveError {
    final raw = bpmErrorPercent;
    final folded = bpmFoldedErrorPercent;
    if (raw == null || folded == null) return null;
    return raw > 3.0 && folded <= 2.0;
  }

  bool? get keyCorrect {
    final tonicLabel = expectedTonic;
    final minorLabel = expectedMinor;
    if (tonicLabel == null || minorLabel == null) return null;
    if (analysis.tonicPitchClass == null || analysis.keyConfidence < 0.25) {
      return false;
    }
    return analysis.tonicPitchClass == tonicLabel &&
        analysis.isMinor == minorLabel;
  }

  bool? get metreCorrect {
    final expected = expectedMeter;
    if (expected == null) return null;
    return analysis.meter == expected;
  }

  double? get beatPhaseErrorMs {
    final bpm = analysis.bpm;
    final phase = analysis.beatOffsetMs;
    if (bpm == null || bpm <= 0 || phase == null) return null;
    final period = 60000.0 / bpm;
    final expected = _number(testCase.expect['beatOffsetMs']) ?? 0.0;
    return _circularDistance(phase, expected, period);
  }

  double? get downbeatPhaseErrorMs {
    final bpm = analysis.bpm;
    final meter = expectedMeter ?? testCase.meter;
    final phase = analysis.downbeatOffsetMs;
    if (bpm == null || bpm <= 0 || phase == null) return null;
    final period = 60000.0 / bpm * meter * 4.0;
    final expected = _number(testCase.expect['downbeatOffsetMs']) ?? 0.0;
    return _circularDistance(phase, expected, period);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': testCase.id,
    'kind': testCase.kind,
    'expectedBpm': expectedBpm,
    'bpmErrorPercent': bpmErrorPercent,
    'bpmFoldedErrorPercent': bpmFoldedErrorPercent,
    'octaveError': octaveError,
    'expectedTonic': expectedTonic,
    'expectedMinor': expectedMinor,
    'keyCorrect': keyCorrect,
    'metreCorrect': metreCorrect,
    'beatPhaseErrorMs': beatPhaseErrorMs,
    'downbeatPhaseErrorMs': downbeatPhaseErrorMs,
    'elapsedMs': elapsedMs,
    'rssBytes': rssBytes,
    'analysis': _snapshot(analysis),
  };
}

Map<String, dynamic> _snapshot(NativeAutomixAnalysis a) => <String, dynamic>{
  'bpm': a.bpm,
  'bpmConfidence': a.bpmConfidence,
  'alternateBpm': a.alternateBpm,
  'beatOffsetMs': a.beatOffsetMs,
  'tonicPitchClass': a.tonicPitchClass,
  'isMinor': a.isMinor,
  'keyConfidence': a.keyConfidence,
  'rmsDb': a.rmsDb,
  'centroidHz': a.centroidHz,
  'onsetRate': a.onsetRate,
  'analyzedSeconds': a.analyzedSeconds,
  'downbeatOffsetMs': a.downbeatOffsetMs,
  'dropCueMs': a.dropCueMs,
  'breakdownCueMs': a.breakdownCueMs,
  'dropConfidence': a.dropConfidence,
  'breakdownConfidence': a.breakdownConfidence,
  'structureRegion': a.structureRegion,
  'structureConfidence': a.structureConfidence,
  'vocalLikelihood': a.vocalLikelihood,
  'vocalConfidence': a.vocalConfidence,
  'tailBpmConfidence': a.tailBpmConfidence,
  'startBpm': a.startBpm,
  'endBpm': a.endBpm,
  'tempoStability': a.tempoStability,
  'startBpmConfidence': a.startBpmConfidence,
  'endBpmConfidence': a.endBpmConfidence,
  'startBeatOffsetMs': a.startBeatOffsetMs,
  'endBeatOffsetMs': a.endBeatOffsetMs,
  'meter': a.meter,
  'sectionCueMs': a.sectionCueMs,
  'sectionCueConfidence': a.sectionCueConfidence,
  'introEdgeRmsDb': a.introEdgeRmsDb,
  'outroEdgeRmsDb': a.outroEdgeRmsDb,
  'introEdgeLufs': a.introEdgeLufs,
  'outroEdgeLufs': a.outroEdgeLufs,
  'introEdgeOnsetRate': a.introEdgeOnsetRate,
  'outroEdgeOnsetRate': a.outroEdgeOnsetRate,
  'energyQuarters': a.energyQuarters,
};

Map<String, dynamic> _summary(List<_Result> results) {
  double? mean(Iterable<double?> values) {
    final present = values.whereType<double>().toList(growable: false);
    if (present.isEmpty) return null;
    return present.reduce((a, b) => a + b) / present.length;
  }

  final bpmErrors = results.map((r) => r.bpmErrorPercent);
  final keyResults = results.map((r) => r.keyCorrect).whereType<bool>();
  final metreResults = results.map((r) => r.metreCorrect).whereType<bool>();
  final octave = results.map((r) => r.octaveError).whereType<bool>();
  final elapsed = results.map((r) => r.elapsedMs.toDouble());
  return <String, dynamic>{
    'cases': results.length,
    'bpmWithin2Percent': bpmErrors
        .whereType<double>()
        .where((value) => value <= 2.0)
        .length,
    'bpmMeasured': bpmErrors.whereType<double>().length,
    'bpmMeanErrorPercent': mean(bpmErrors),
    'bpmOctaveErrors': octave.where((value) => value).length,
    'keyCorrect': keyResults.where((value) => value).length,
    'keyMeasured': keyResults.length,
    'metreCorrect': metreResults.where((value) => value).length,
    'metreMeasured': metreResults.length,
    'meanElapsedMs': mean(elapsed),
    'peakRssBytes': results
        .map((r) => r.rssBytes)
        .reduce((a, b) => math.max(a, b)),
  };
}

void _printTable(List<_Result> results) {
  stdout.writeln(
    '${'case'.padRight(24)} ${'bpm'.padLeft(7)} ${'err%'.padLeft(6)} '
    '${'oct'.padLeft(4)} ${'key'.padLeft(6)} ${'metre'.padLeft(5)} '
    '${'beat'.padLeft(7)} ${'ms'.padLeft(7)} ${'rssMB'.padLeft(7)}',
  );
  for (final result in results) {
    final a = result.analysis;
    String number(double? value, [int digits = 1]) =>
        value == null || !value.isFinite ? '-' : value.toStringAsFixed(digits);
    final bpm = number(a.bpm);
    final error = number(result.bpmErrorPercent, 2);
    final octave = result.octaveError == true ? 'yes' : '-';
    final key = result.keyCorrect == null
        ? '-'
        : (result.keyCorrect! ? 'ok' : 'x');
    final metre = result.metreCorrect == null
        ? '-'
        : (result.metreCorrect! ? 'ok' : 'x');
    final beat = number(result.beatPhaseErrorMs, 0);
    stdout.writeln(
      '${result.testCase.id.padRight(24)} ${bpm.padLeft(7)} '
      '${error.padLeft(6)} ${octave.padLeft(4)} ${key.padLeft(6)} '
      '${metre.padLeft(5)} ${beat.padLeft(7)} '
      '${result.elapsedMs.toString().padLeft(7)} '
      '${(result.rssBytes / (1024 * 1024)).toStringAsFixed(1).padLeft(7)}',
    );
  }
  final summary = _summary(results);
  stdout.writeln(
    'summary: ${summary['cases']} cases, '
    'BPM<=2% ${summary['bpmWithin2Percent']}/${summary['bpmMeasured']} '
    '(mean ${_fixed(summary['bpmMeanErrorPercent'])}, '
    'octave ${summary['bpmOctaveErrors']}), '
    'key ${summary['keyCorrect']}/${summary['keyMeasured']}, '
    'metre ${summary['metreCorrect']}/${summary['metreMeasured']}, '
    'mean ${_fixed(summary['meanElapsedMs'])} ms, '
    'peak RSS ${((summary['peakRssBytes'] as int) / (1024 * 1024)).toStringAsFixed(1)} MB',
  );
}

String _fixed(Object? value) {
  if (value is! num || !value.isFinite) return '-';
  return value.toStringAsFixed(1);
}

List<String> _checkGolden(List<_Result> results, Map<String, dynamic> cases) {
  final failures = <String>[];
  for (final result in results) {
    final goldenCase = cases[result.testCase.id];
    if (goldenCase is! Map) {
      failures.add('${result.testCase.id}: missing from golden');
      continue;
    }
    final expected = (goldenCase['analysis'] as Map?)?.cast<String, dynamic>();
    if (expected == null) {
      failures.add('${result.testCase.id}: golden has no analysis');
      continue;
    }
    final actual = _snapshot(result.analysis);
    for (final key in expected.keys) {
      final exp = expected[key];
      final got = actual[key];
      final tolerance = _tolerance(key);
      if (got is List) {
        if (exp is! List || got.length != exp.length) {
          failures.add('${result.testCase.id}.$key: shape changed');
          continue;
        }
        for (var i = 0; i < got.length; i++) {
          if (!_within(got[i], exp[i], tolerance)) {
            failures.add(
              '${result.testCase.id}.$key[$i]: got ${got[i]}, expected $exp',
            );
          }
        }
        continue;
      }
      if (!_within(got, exp, tolerance)) {
        failures.add(
          '${result.testCase.id}.$key: got $got, expected $exp '
          '(tolerance $tolerance)',
        );
      }
    }
  }
  return failures;
}

double _tolerance(String key) => switch (key) {
  'bpm' || 'alternateBpm' || 'startBpm' || 'endBpm' => 0.02,
  'beatOffsetMs' ||
  'downbeatOffsetMs' ||
  'startBeatOffsetMs' ||
  'endBeatOffsetMs' ||
  'dropCueMs' ||
  'breakdownCueMs' ||
  'sectionCueMs' => 25.0,
  'rmsDb' || 'introEdgeRmsDb' || 'outroEdgeRmsDb' => 1.5,
  'centroidHz' => 75.0,
  'onsetRate' || 'introEdgeOnsetRate' || 'outroEdgeOnsetRate' => 0.5,
  'introEdgeLufs' || 'outroEdgeLufs' => 1.5,
  'energyQuarters' => 1.0,
  'tonicPitchClass' || 'isMinor' || 'meter' || 'structureRegion' => 0.0,
  // Confidences, LUFS and analyzedSeconds are compared numerically.
  _ => 0.05,
};

bool _within(Object? got, Object? expected, double tolerance) {
  if (got == null || expected == null) return got == expected;
  if (got is bool || expected is bool) return got == expected;
  if (got is num && expected is num) {
    if (!got.isFinite || !expected.isFinite) {
      return got.isFinite == expected.isFinite;
    }
    if (tolerance == 0.0) return got == expected;
    return (got - expected).abs() <= tolerance;
  }
  return got == expected;
}

double? _number(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

int? _integer(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toInt();
}

double _circularDistance(double a, double b, double period) {
  if (period <= 0) return (a - b).abs();
  var delta = (a - b).abs() % period;
  if (delta > period / 2) delta = period - delta;
  return delta;
}
