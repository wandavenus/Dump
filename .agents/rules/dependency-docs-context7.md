---
description: Look up official dependency/API docs with Context7 and match them to the versions pinned in this repo before changing code.
trigger: always
---

# Dependency Docs via Context7

User directive: before making code changes that touch a dependency's API, look
up its official docs with Context7, then match the docs against the version this
repo actually resolves. Never code against APIs from a newer or older release
than the one pinned here.

## When to use it

Use Context7 for library/framework/SDK/CLI/cloud topics: API signatures,
configuration, version migrations, setup steps, and library-specific debugging.
Skip it for refactors, business-logic debugging, code review, or general
programming concepts — and skip it when the change touches no third-party API.

## Version matching protocol

1. **Read the resolved version first** (repo source of truth, not the caret range):
   - Dart/Flutter: `pubspec.lock` (`version:` per package); SDK ceiling from
     `pubspec.yaml` `environment.sdk`.
   - Media3: `android/build.gradle` → `ext.media3Version` (currently `1.11.1`).
   - AGP / Kotlin: `android/settings.gradle` plugins block.
   - Flutter engine: `flutter --version`.
   - Native deps: `native_audio_runtime/hook/build.dart`, `android/app/src/main/cpp/CMakeLists.txt`.
2. **Resolve the library ID** with Context7 `resolve-library-id`; prefer an entry
   that lists a matching version (e.g. `/androidx/media` exposes `1.11.1`).
3. **Query with the version in the question** (e.g. "Media3 1.11 MediaSession
   custom layout", "Flutter 3.47 SliverList") via `query-docs`.
4. **Reconcile before coding**:
   - Docs match pinned version → proceed.
   - Docs are newer → do not adopt new APIs; verify against local sources
     (`~/.pub-cache/hosted/pub.dev/<pkg>-<version>/`) or the Gradle cache.
   - Docs are older → check the local source as authoritative.
5. **State the version in the change** when an API choice depends on it, so the
   next session can re-verify after a dependency bump.

## Known-good Context7 IDs

| Dependency | ID |
| --- | --- |
| Flutter framework | `/flutter/website` or `/websites/api_flutter_dev` |
| Flutter first-party packages | `/flutter/packages` |
| AndroidX Media3 | `/androidx/media` (versions `1.10.1`, `1.11.1`) |
| Dart `http` | `/websites/pub_dev_http` |

These are starting points only; re-resolve when a version is missing from the
list. Pinned versions are tracked in `.agents/memory/dependency-docs-context7.md`.
