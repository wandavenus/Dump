// AUTO GENERATED FILE, DO NOT EDIT BY HAND.
//
// Mirrors `package:ffigen` output for `src/native_audio_runtime.h`.
// Regenerate with `dart run ffigen --config ffigen.yaml` once libclang is
// available in the build environment; until then this file is maintained
// by hand and MUST stay in sync with the header, function-for-function.
// ignore_for_file: type=lint, unused_import
import 'dart:ffi' as ffi;

/// Initialize the native runtime. Idempotent and thread-safe.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_init();

/// Tear down the native runtime and clear the module registry.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_dispose();

/// Returns 1 if the runtime is currently initialized, 0 otherwise.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_is_initialized();

/// Static runtime version string. Owned by native code — do not free.
@ffi.Native<ffi.Pointer<ffi.Char> Function()>()
external ffi.Pointer<ffi.Char> native_runtime_get_version();

/// Number of capability entries known to the runtime.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_capability_count();

/// Capability key at `index`, or nullptr if out of range.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.Int32)>()
external ffi.Pointer<ffi.Char> native_runtime_capability_key(int index);

/// Whether the capability at `index` is supported.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int native_runtime_capability_supported(int index);

/// Register a module id with the runtime.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>()
external int native_runtime_register_module(ffi.Pointer<ffi.Char> moduleId);

/// Number of modules currently registered.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_module_count();

/// Module id at `index` in registration order, or nullptr if out of range.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.Int32)>()
external ffi.Pointer<ffi.Char> native_runtime_module_id_at(int index);

/// Status code of the most recent runtime call.
@ffi.Native<ffi.Int32 Function()>()
external int native_runtime_last_status();
