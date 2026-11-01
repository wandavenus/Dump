---
name: CI quality gates
description: Required checks for pull requests and the change-detection regression that previously skipped Dart-changing PRs.
---

# CI quality gates

The `.github/workflows/ci.yml` workflow runs on pull requests to `main` and manual dispatch. Keep Flutter tests, Kotlin unit tests, the Android debug APK build, and FFmpeg/license packaging verification enabled for every run unless a deliberate path filter is introduced with explicit coverage for all affected integration files.

A prior `dart_changed` detector was inverted at its consumers: `dart_changed=true` made the Flutter test and APK/package-verification steps skip, while changes without Dart edits ran them. GitHub evaluates step `if` expressions as conditions; a false condition skips that step. Avoid gating core integration checks on the inverse of the changed-source signal.

When considering CI time optimization, keep analysis and the relevant test/build gates aligned with changes to `lib/`, `test/`, `android/`, `native_audio_runtime/`, build scripts, and dependency manifests. Do not infer that a skipped check passed.
