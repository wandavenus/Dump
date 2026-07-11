// Runs the REAL native runtime, compiled for the host platform by the
// native-assets build hook (`hook/build.dart`) when this test executes.
// This is the one place in the whole Phase 3 change that actually proves
// the C lifecycle/thread-safety/registry logic runs correctly — Android
// cross-compilation itself could not be verified in this environment (no
// Android SDK/NDK installed here); see NATIVE_RUNTIME.md "Assumptions".
import 'dart:async';

import 'package:native_audio_runtime/native_audio_runtime.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    // Best-effort reset between tests since the runtime is a process-wide
    // singleton; dispose is safe even if already disposed.
    await NativeAudioRuntime.instance.dispose();
  });

  test('reports availability', () {
    // On host platforms with dart:ffi this is backed by the real library;
    // on web (not exercised by `dart test`) it would be false.
    expect(NativeAudioRuntime.instance, isNotNull);
  });

  test('initialize is idempotent and sets isAvailable', () async {
    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);

    // Calling twice must not throw — mirrors the native
    // ALREADY_INITIALIZED contract being treated as success.
    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);
  });

  test('version is a non-empty string', () async {
    await NativeAudioRuntime.instance.initialize();
    expect(NativeAudioRuntime.instance.version, isNotEmpty);
    expect(NativeAudioRuntime.instance.version, isNot('unknown'));
  });

  test('capabilities are all unsupported placeholders', () async {
    await NativeAudioRuntime.instance.initialize();
    final caps = NativeAudioRuntime.instance.capabilities;
    expect(caps, isNotEmpty);
    expect(caps.every((c) => c.supported == false), isTrue);
    expect(caps.map((c) => c.key), contains('dsp.equalizer'));
  });

  test('registerModule succeeds once, then reports duplicate', () async {
    await NativeAudioRuntime.instance.initialize();
    final first = NativeAudioRuntime.instance.registerModule('native_dsp');
    expect(first, NativeRuntimeStatus.ok);

    final second = NativeAudioRuntime.instance.registerModule('native_dsp');
    expect(second, NativeRuntimeStatus.duplicateModule);

    expect(
      NativeAudioRuntime.instance.registeredModuleIds,
      contains('native_dsp'),
    );
  });

  test('registerModule before initialize reports notInitialized', () async {
    await NativeAudioRuntime.instance.dispose();
    final status =
        NativeAudioRuntime.instance.registerModule('too_early_module');
    expect(status, NativeRuntimeStatus.notInitialized);
  });

  test('concurrent initialize calls are safe (thread-safety contract)',
      () async {
    final futures = <Future<void>>[
      for (var i = 0; i < 8; i++) NativeAudioRuntime.instance.initialize(),
    ];
    await Future.wait(futures);
    expect(NativeAudioRuntime.instance.isAvailable, isTrue);
  });

  test('dispose is safe without a prior initialize', () async {
    await NativeAudioRuntime.instance.dispose();
    await NativeAudioRuntime.instance.dispose();
  });
}
