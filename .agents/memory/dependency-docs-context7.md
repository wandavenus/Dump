---
name: Dependency docs via Context7
description: Check official docs with Context7 and match them to the dependency versions pinned in this repo before changing code.
---

User directive (2026-10-30): use Context7 to find official documentation and the
API of the dependency versions in use **before** making code changes, and match
the docs to the versions in the repository. Canonical rule:
`.agents/rules/dependency-docs-context7.md` (loaded via `opencode.json`).

**Why:** this repo pins specific releases — Media3 `1.11.1`, Kotlin `2.4.21`,
AGP `9.4.1`, Flutter `3.47.7` / Dart `3.13.5`, and caret-ranged pub packages.
Docs for a different release routinely show renamed/removed APIs, and the
Android Media3 surface in particular changes between minor versions.

**Pinned versions at the time of writing:**

| Dependency | Version | Source |
| --- | --- | --- |
| Flutter | 3.47.7 (Dart 3.13.5) | `flutter --version` |
| AndroidX Media3 | 1.11.1 | `android/build.gradle` `ext.media3Version` |
| AGP | 9.4.1 | `android/settings.gradle` |
| Kotlin | 2.4.21 | `android/settings.gradle` |
| compileSdk / NDK | 36 / 28.2.13676358 | `android/app/build.gradle` |
| intl | 0.20.3 | `pubspec.lock` |
| http | 1.6.0 | `pubspec.lock` |
| path | 1.9.1 | `pubspec.lock` |
| path_provider | 2.1.6 | `pubspec.lock` |
| package_info_plus | 10.2.2 | `pubspec.lock` |
| shared_preferences | 2.5.6 | `pubspec.lock` |
| permission_handler | 12.0.3 | `pubspec.lock` |
| audio_session | 0.2.4 | `pubspec.lock` |
| gal | 2.3.3 | `pubspec.lock` |
| url_launcher | 6.3.3 | `pubspec.lock` |
| font_awesome_flutter | 11.0.0 | `pubspec.lock` |
| flutter_lints | 6.0.0 | `pubspec.lock` |

Verified Context7 IDs: `/flutter/website`, `/websites/api_flutter_dev`,
`/flutter/packages`, `/androidx/media` (lists `1.10.1`, `1.11.1`),
`/websites/pub_dev_http`.

**How to apply:** read the resolved version from `pubspec.lock` /
`android/build.gradle` / `android/settings.gradle` first, resolve the library ID,
ask the Context7 query with that version, then reconcile — if the docs are newer
than the pin, check local sources (`~/.pub-cache/hosted/pub.dev/<pkg>-<version>/`,
Gradle cache) instead of adopting the newer API. Re-check this table after any
dependency bump.
