---
name: Project analyzer scope
description: Scope Dart analyzer to the app directories so the local Flutter SDK checkout is not counted as project diagnostics.
---

Run project-level Dart analysis with explicit `lib` and `test` targets rather than from the repository root.

**Why:** The workspace contains a manual Flutter SDK checkout under `flutter-ws/`. A root-level `dart analyze` recursively includes SDK packages, generated SDK files, benchmarks, examples, and internal tests, producing a misleading diagnostic total.

**How to apply:** Use `dart analyze --format=json lib test` for project reports. Treat diagnostics under `flutter-ws/` as SDK-scope findings, not application findings.