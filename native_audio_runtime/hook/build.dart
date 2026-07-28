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
      sources: [
        'src/$packageName.c', // lifecycle, version, capability, module registry
        'src/audio_buffer.c', // NarAudioBuffer — interleaved PCM buffer
        'src/dsp_pipeline.c', // DSP processing chain
        'src/gain_processor.c', // Gain processor (Phase 4: pipeline validator)
        'src/replaygain_processor.c', // ReplayGain processor (Phase 8: metadata gain)
        'src/biquad_filter.c', // Biquad coefficient computation (shared by crossfeed/loudness)
        'src/comp_processor.c', // Compressor processor (Phase 6)
        'src/crossfeed_processor.c', // Crossfeed processor (Phase 7)
        'src/limiter_processor.c', // Look-ahead limiter processor (Phase 6)
        'src/soft_clipper_processor.c', // Soft clipper processor (Phase 6)
        'src/loudness_processor.c', // Loudness Normalization (Phase 8.5)
        'src/aaudio_probe.c', // AAudio exclusive/MMAP diagnostic probe
        // JNI bridge — NativeDspAudioProcessor.kt calls into this .so via
        // System.loadLibrary("native_audio_runtime") on Android; it is the
        // JVM/JNI counterpart to the Dart FFI entry points in this same
        // library (see native_dsp_jni.c header comment). Unlike the other
        // files above, this one unconditionally includes <jni.h>, which only
        // exists in an Android NDK toolchain — it must be Android-only or it
        // breaks Linux/Windows/macOS/host-test builds of this package.
        if (input.config.buildCodeAssets &&
            input.config.code.targetOS == OS.android)
          'src/native_dsp_jni.c',
        // ARM64 NEON Assembly kernels — compiled by clang's integrated assembler.
        // Compiled only for arm64-v8a; the file is guarded by #ifdef __aarch64__
        // so x86_64 host builds (unit tests) get an empty translation unit.
        'src/neon_kernels.S', // nar_gain_apply_neon, nar_biquad_stereo_neon
      ],
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
