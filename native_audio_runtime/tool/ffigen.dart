// Copyright (c) 2025, the native_audio_runtime authors.
// Use of this source code is governed by the project LICENSE.
//
// Generates FFI bindings for all public C headers of native_audio_runtime
// using package:ffigen. Run from the package root:
//
//   dart run tool/ffigen.dart
//
// This replaces the hand-maintained
// lib/native_audio_runtime_bindings_generated.dart with a properly generated
// file under lib/src/third_party/.

import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');

  // All public C surface headers — each exposes FFI_PLUGIN_EXPORT symbols.
  final entryHeaders = [
    packageRoot.resolve('src/native_audio_runtime.h'),
    packageRoot.resolve('src/audio_buffer.h'),
    packageRoot.resolve('src/dsp_pipeline.h'),
    packageRoot.resolve('src/gain_processor.h'),
    packageRoot.resolve('src/comp_processor.h'),
    packageRoot.resolve('src/crossfeed_processor.h'),
    packageRoot.resolve('src/limiter_processor.h'),
    packageRoot.resolve('src/loudness_processor.h'),
    packageRoot.resolve('src/replaygain_processor.h'),
    packageRoot.resolve('src/soft_clipper_processor.h'),
    packageRoot.resolve('src/aaudio_probe.h'),
  ];

  // Only expose symbols that appear in the hand-written bindings — no
  // internal-only symbols, vtable helpers, or pipeline-internal functions.
  const includedFunctions = {
    // native_audio_runtime.h
    'native_runtime_init',
    'native_runtime_dispose',
    'native_runtime_is_initialized',
    'native_runtime_get_version',
    'native_runtime_capability_count',
    'native_runtime_capability_key',
    'native_runtime_capability_supported',
    'native_runtime_register_module',
    'native_runtime_module_count',
    'native_runtime_module_id_at',
    'native_runtime_last_status',
    // audio_buffer.h
    'nar_audio_buffer_create',
    'nar_audio_buffer_destroy',
    'nar_audio_buffer_data',
    'nar_audio_buffer_capacity_frames',
    'nar_audio_buffer_frame_count',
    'nar_audio_buffer_set_frame_count',
    'nar_audio_buffer_channel_count',
    'nar_audio_buffer_sample_rate',
    'nar_audio_buffer_format',
    'nar_audio_buffer_timestamp_us',
    'nar_audio_buffer_set_timestamp_us',
    // dsp_pipeline.h
    'nar_dsp_pipeline_init',
    'nar_dsp_pipeline_is_initialized',
    'nar_dsp_pipeline_process',
    'nar_dsp_pipeline_process_stream',
    'nar_dsp_pipeline_process_raw',
    'nar_dsp_pipeline_process_raw_stream',
    'nar_dsp_pipeline_reset',
    'nar_dsp_pipeline_dispose',
    'nar_dsp_pipeline_set_enabled',
    'nar_dsp_pipeline_is_enabled',
    'nar_dsp_pipeline_total_latency_frames',
    'nar_dsp_pipeline_processor_count',
    'nar_dsp_pipeline_processor_id_at',
    // gain_processor.h
    'nar_gain_processor_register_internal',
    'nar_gain_processor_set_gain_db',
    'nar_gain_processor_get_gain_db',
    'nar_gain_processor_set_bypass',
    'nar_gain_processor_get_bypass',
    // comp_processor.h
    'nar_comp_processor_register_internal',
    'nar_comp_set_params',
    'nar_comp_set_bypass',
    'nar_comp_get_bypass',
    // crossfeed_processor.h
    'nar_crossfeed_processor_register_internal',
    'nar_crossfeed_set_params',
    'nar_crossfeed_set_bypass',
    'nar_crossfeed_get_bypass',
    // limiter_processor.h
    'nar_limiter_processor_register_internal',
    'nar_limiter_set_params',
    'nar_limiter_set_bypass',
    'nar_limiter_get_bypass',
    'nar_limiter_lookahead_frames',
    // loudness_processor.h
    'nar_loudness_processor_register_internal',
    'nar_loudness_set_target_lufs',
    'nar_loudness_set_bypass',
    'nar_loudness_get_bypass',
    'nar_loudness_set_sample_rate',
    'nar_loudness_get_measured_lufs',
    'nar_loudness_get_applied_gain_db',
    'nar_loudness_reset',
    // replaygain_processor.h
    'nar_replaygain_processor_register_internal',
    'nar_replaygain_set_gain',
    'nar_replaygain_set_bypass',
    'nar_replaygain_get_bypass',
    // soft_clipper_processor.h
    'nar_soft_clipper_processor_register_internal',
    'nar_soft_clipper_set_threshold_db',
    'nar_soft_clipper_get_threshold_db',
    'nar_soft_clipper_set_bypass',
    'nar_soft_clipper_get_bypass',
    // aaudio_probe.h
    'native_runtime_aaudio_probe',
    'native_runtime_aaudio_last_sharing_mode',
    'native_runtime_aaudio_last_performance_mode',
    'native_runtime_aaudio_last_error',
  };

  final bindingsOutput = packageRoot
      .resolve('lib/src/third_party/native_audio_runtime.g.dart');

  FfiGenerator(
    headers: Headers(
      entryPoints: entryHeaders,
      // Only resolve symbols within our own src/ — ignore any transitive
      // system headers (stdint.h, etc.).
      include: (header) {
        final path = header.toFilePath();
        return path.contains('/native_audio_runtime/src/');
      },
      ignoreSourceErrors: true,
    ),
    functions: Functions(
      include: (decl) => includedFunctions.contains(decl.originalName),
      // isLeaf: all DSP functions are hot-path leaf calls — they never call
      // back into Dart and do not block, so marking them leaf avoids the
      // overhead of entering/exiting the Dart VM on each call.
      isLeaf: (_) => true,
    ),
    structs: Structs(
      // NarAudioBuffer is opaque — expose it so Pointer<NarAudioBuffer> works.
      include: (decl) => decl.originalName == 'NarAudioBuffer',
    ),
    enums: Enums(
      include: (decl) => const {
        'NativeRuntimeStatus',
        'NarSampleFormat',
        'NarAAudioProbeResult',
      }.contains(decl.originalName),
    ),
    output: Output(
      dartFile: bindingsOutput,
      format: true,
      preamble: '''
// AUTO-GENERATED FILE — DO NOT EDIT BY HAND.
//
// Generated by package:ffigen via tool/ffigen.dart.
// To regenerate: dart run tool/ffigen.dart
//
// Bindings for the native_audio_runtime C DSP library.
// Covers: native_audio_runtime.h, audio_buffer.h, dsp_pipeline.h,
//         gain/comp/crossfeed/limiter/loudness/replaygain/soft_clipper
//         processors, and aaudio_probe.h.
//
// ignore_for_file: type=lint, unused_import, unused_element,
//   camel_case_types, non_constant_identifier_names,
//   deprecated_member_use_from_same_package, experimental_member_use
''',
    ),
  ).generate();

  stdout.writeln('Generated: ${bindingsOutput.toFilePath()}');
}
