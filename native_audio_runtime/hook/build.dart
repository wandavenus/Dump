import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      // Phase 4: all C translation units in the native runtime.
      // Order matters only for the compiler; link order is handled by the
      // native-assets toolchain. audio_buffer.c, dsp_pipeline.c, and
      // gain_processor.c are compiled as separate TUs to keep each file's
      // scope explicit (matching the header-per-file contract).
      sources: [
        'src/$packageName.c',      // lifecycle, version, capability, module registry
        'src/audio_buffer.c',      // NarAudioBuffer — interleaved PCM buffer
        'src/dsp_pipeline.c',      // DSP processing chain
        'src/gain_processor.c',    // Gain processor (Phase 4: pipeline validator)
        'src/replaygain_processor.c',   // ReplayGain processor (Phase 8: metadata gain)
        'src/biquad_filter.c',          // Biquad coefficient computation (Phase 5)
        'src/peq_processor.c',          // Parametric EQ processor (Phase 5)
        'src/comp_processor.c',         // Compressor processor (Phase 6)
        'src/crossfeed_processor.c',    // Crossfeed processor (Phase 7)
        'src/limiter_processor.c',      // Look-ahead limiter processor (Phase 6)
        'src/soft_clipper_processor.c', // Soft clipper processor (Phase 6)
      ],
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
