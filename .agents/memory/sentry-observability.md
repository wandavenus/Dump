---
name: Sentry observability
description: Sentry Flutter SDK setup, error routing, privacy defaults, native crash handling, and build-time DSN handoff.
---

# Sentry observability

## Runtime integration

- App dependency is sentry_flutter ^10.2.0.
- lib/main/main.dart initializes Sentry after WidgetsFlutterBinding.ensureInitialized() and before startup services.
- DSN source is const String.fromEnvironment('SENTRY_DSN'); it must be supplied with Flutter's --dart-define=SENTRY_DSN=....
- Empty DSN disables event delivery. Initialization is fail-open so observability cannot prevent the player from launching.
- Release environment is production; non-release builds use development.
- PII collection is disabled. Tracing is left disabled (default) to avoid sending performance spans or adding unnecessary runtime/network cost.
- Native crash handling is enabled; Sentry Flutter includes Android native support for Java/Kotlin/C/C++ errors. Native crashes are device/runtime-level and need release/device validation.

## Error routing

- FlutterError.onError forwards framework exceptions to both Sentry.captureException and LogService.
- PlatformDispatcher.instance.onError forwards uncaught main-isolate errors to both.
- The existing root runZonedGuarded callback also forwards uncaught zone errors to Sentry and preserves LogService logging.
- Avoid adding another global error hook without preserving these forwarding paths; otherwise one reporter may silently replace another.

## Build configuration

- Dump repository environment production owns the non-secret SENTRY_DSN variable.
- .github/workflows/trigger-public-builder.yml reads vars.SENTRY_DSN and sends it in the build-private-source repository-dispatch payload to wandavenus/Noisegraph.
- Noisegraph .github/workflows/build-apk.yml injects the received DSN through --dart-define=SENTRY_DSN=....
- Never place SENTRY_AUTH_TOKEN in Dart defines, app assets, Gradle properties, or dispatch payloads.
- The APK build uses --obfuscate --split-debug-info=build/debug-info; upload the build's Dart debug-info directory to Sentry to make obfuscated Dart stack traces readable. Debug symbol upload is not part of this runtime SDK integration yet.

## Verification

- Run flutter pub get to resolve the new package and regenerate pubspec.lock.
- Run flutter analyze (user directive: do not run APK builds while working on Dart/Flutter changes).
- Validate native Android crash capture on a release APK/device separately; never deliberately crash a user's production install.
