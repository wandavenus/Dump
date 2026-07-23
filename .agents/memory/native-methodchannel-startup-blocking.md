---
    name: Native MethodChannel startup blocking
    description: Any awaited MethodChannel round-trip added to the synchronous startup chain (main -> PlaybackManager.initialize -> NativeModuleRegistry.initializeAll) can hang the whole app (black screen, no crash) if the native reply is ever delayed or never sent, because neither Dart's await nor the registry's try/catch has a timeout.
    ---

    ## Lesson
    `main()` awaits `PlaybackManager.initialize()` directly before `runApp()`, and
    `NativeModuleRegistry.initializeAll()` awaits each registered `NativeModule.initialize()`
    in sequence with only a try/catch (no timeout). A try/catch does NOT protect against a
    Future that never completes — only against one that throws.

    FFI-based modules (e.g. NativeDspBridge, using package:native_audio_runtime) are safe here
    because the native call is synchronous/local and always resolves fast. A genuine
    MethodChannel round-trip to platform (Kotlin/Swift) code is a different risk class: if the
    native side ever fails to call `result.success()`/`result.error()` (or the reply is
    delayed under device throttling/cold-start contention), the Dart `await` hangs forever
    with zero error signal — the app shows a black screen with no crash, because `runApp()`
    is never reached.

    **Why:** discovered when Phase 9's FfmpegDecoderBridge.initialize() added the first
    awaited MethodChannel call in this startup chain; it had no timeout and could stall the
    whole app indefinitely.

    **How to apply:** any new NativeModule whose `initialize()` does a real platform-channel
    round-trip must (1) never await that round-trip inline inside `initialize()` — fire it in
    the background via `unawaited()` and update capabilities/status once it resolves, and
    (2) wrap the native call with `.timeout(...)` and fail open (mark unavailable) on
    timeout/error. `initialize()` itself should return immediately with a safe default status.
    