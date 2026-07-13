---
name: native_audio_runtime host test environment quirks
description: How to actually run `dart test` for native_audio_runtime in this sandbox — SDK version and clang-shim gotchas.
---

The system-default `dart` (from the Nix Flutter 3.32.0 wrapper) is 3.8.0, but
`native_audio_runtime/pubspec.yaml` requires `^3.12.2` — `dart pub get` fails
version solving with the default PATH. The manually-installed Flutter at
`/home/runner/flutter/bin` (see `flutter-manual-install.md`) ships a matching
Dart 3.12.2 SDK. Use that PATH entry for any `native_audio_runtime` Dart work:

```
export PATH="/home/runner/flutter/bin:/tmp:$PATH"
```

Also `native_toolchain_c` (native-assets build hooks) looks for a literal
`clang` on PATH; this sandbox only has `gcc`. Symlink it once per session:

```
ln -sf $(which gcc) /tmp/clang
```

With both in place, `dart pub get` and `dart test test/native_audio_runtime_test.dart`
compile the native sources with gcc-as-clang and actually run the FFI test
suite — this is the only way in this sandbox to get real compile+run
verification for changes under `native_audio_runtime/src/*.c`.
