---
name: CI quality gates
description: Required checks for pull requests and the change-detection regression that previously skipped Dart-changing PRs.
---

# CI quality gates

The `.github/workflows/ci.yml` workflow runs on pull requests to `main` and manual dispatch. Keep Flutter tests, Kotlin unit tests, the Android debug APK build, and FFmpeg/license packaging verification enabled for every run unless a deliberate path filter is introduced with explicit coverage for all affected integration files.

A prior `dart_changed` detector was inverted at its consumers: `dart_changed=true` made the Flutter test and APK/package-verification steps skip, while changes without Dart edits ran them. GitHub evaluates step `if` expressions as conditions; a false condition skips that step. Avoid gating core integration checks on the inverse of the changed-source signal.

When considering CI time optimization, keep analysis and the relevant test/build gates aligned with changes to `lib/`, `test/`, `android/`, `native_audio_runtime/`, build scripts, and dependency manifests. Do not infer that a skipped check passed.

Use `environment.flutter` in `pubspec.yaml` as the single exact Flutter SDK pin; every workflow invoking `subosito/flutter-action` should use `flutter-version-file: pubspec.yaml`. Refresh Actions whose runtime is Node 20 before GitHub removes it; current repository-approved majors are `setup-java@v6`, `setup-gradle@v6`, `upload-artifact@v7`, `download-artifact@v8`, `upload-pages-artifact@v5`, and `deploy-pages@v5`. Keep Gradle caching on the open `basic` provider unless the repository explicitly approves another provider.

Limit `pages: write` and `id-token: write` to the Pages deployment job, and omit CodeQL `packages: read` unless private CodeQL packs or GitHub Packages are actually added. Build `repository-dispatch` payloads with `jq --arg` rather than interpolating refs into a JSON literal.

For Android release builds, keep signing secrets in the build job with `contents: read`; upload the signed APK as a short-retention artifact, then create the draft release in a separate job with `contents: write` only. Use a random delimiter when writing commit messages to `GITHUB_OUTPUT`.
