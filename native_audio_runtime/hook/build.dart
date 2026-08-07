import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    // comp_processor.c, crossfeed_processor.c, dsp_pipeline.c,
    // limiter_processor.c, loudness_processor.c, native_audio_runtime.c,
    // and soft_clipper_processor.c all guard their debug
    // logging with `#if defined(__ANDROID__)` and call
    // `__android_log_print()` from <android/log.h> on that branch. That
    // symbol lives in Android's `liblog.so`, which is NOT linked
    // automatically — every C translation unit that references it must be
    // linked against `-llog` on Android or the resulting shared library
    // ends up with an unresolved dynamic symbol. Historically this was only
    // exposed at runtime (dlopen/symbol-lookup failure inside
    // NativeReplayGain, NativeLoudnessNorm, etc. the first time one of those
    // control paths ran), not at compile time, which is why it went
    // unnoticed until a fresh cold start actually exercised the code path.
    // See MEMORY.md "native build __android_log_print / liblog link".
    //
    // `input.config.code` is only populated when the invoker actually wants
    // a code asset (native library) built — e.g. `flutter build web` sends
    // no code-asset config at all, and touching `.code` unconditionally
    // throws a null-check error there. Guard on `buildCodeAssets` first so
    // web builds (which never compile this package's C sources) keep working.
    final targetOS = input.config.buildCodeAssets
        ? input.config.code.targetOS
        : null;
    final sources = <String>[
      'src/$packageName.c',
      'src/audio_buffer.c',
      'src/dsp_pipeline.c',
      'src/gain_processor.c',
      'src/replaygain_processor.c',
      'src/biquad_filter.c',
      'src/comp_processor.c',
      'src/crossfeed_processor.c',
      'src/limiter_processor.c',
      'src/soft_clipper_processor.c',
      'src/loudness_processor.c',
      'src/aaudio_probe.c',
      if (targetOS == OS.android) 'src/native_dsp_jni.c',
      'src/neon_kernels.S',
    ];
    if (targetOS == OS.linux &&
        await _buildLinuxWithSystemClang(input, output, sources)) {
      return;
    }

    final libraries = <String>[
      if (input.config.buildCodeAssets &&
          input.config.code.targetOS == OS.android) ...[
        'log',
        // aaudio_probe.c calls dlopen()/dlsym()/dlclose() to probe
        // libaaudio.so's actual granted sharing mode at runtime (see
        // src/aaudio_probe.h) — those symbols live in libdl on Android.
        'dl',
      ],
    ];
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      // Phase 4: all C translation units in the native runtime.
      // Order matters only for the compiler; link order is handled by the
      // native-assets toolchain. audio_buffer.c, dsp_pipeline.c, and
      // gain_processor.c are compiled as separate TUs to keep each file's
      // scope explicit (matching the header-per-file contract).
      sources: sources,
      libraries: libraries,
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        // ignore: avoid_print
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

Future<bool> _buildLinuxWithSystemClang(
  BuildInput input,
  BuildOutputBuilder output,
  List<String> sources,
) async {
  final clang = _findHostClang();
  if (clang == null) return false;

  final outDir = Directory.fromUri(input.outputDirectory);
  await outDir.create(recursive: true);
  final outFile = input.outputDirectory.resolve('lib${input.packageName}.so');
  final sourceUris = [
    for (final source in sources)
      input.packageRoot.resolveUri(Uri.file(source)),
  ];
  final args = <String>[
    '-fPIC',
    '-O3',
    '-DRELEASE',
    '-DNDEBUG',
    for (final source in sourceUris) source.toFilePath(),
    '-shared',
    '-o',
    outFile.toFilePath(),
    r'-Wl,-rpath,$ORIGIN',
  ];
  final result = await Process.run(clang, args);
  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    throw ProcessException(
      clang,
      args,
      'Linux native build failed',
      result.exitCode,
    );
  }
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: '${input.packageName}_bindings_generated.dart',
      file: outFile,
      linkMode: DynamicLoadingBundled(),
    ),
  );
  output.dependencies.addAll(sourceUris);
  return true;
}

String? _findHostClang() {
  const candidates = <String>[
    '/usr/bin/clang',
    '/usr/lib/llvm-20/bin/clang',
    '/usr/lib/llvm-19/bin/clang',
    '/usr/lib/llvm-18/bin/clang',
    '/usr/lib/llvm-17/bin/clang',
    '/usr/lib/llvm-16/bin/clang',
    '/usr/lib/llvm-15/bin/clang',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}
