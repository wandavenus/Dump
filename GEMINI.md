# Project Instructions (GEMINI.md)

This file contains team-shared architectural patterns, development workflows, coding conventions, and repository guidelines. All developers and AI agents must strictly follow these instructions.

---

## 1. Project Overview & Architecture

### High-Level Architecture
- **Framework:** Flutter (Dart) with a layered clean architecture.
- **State Management:** *[Insert State Management: e.g., Bloc, Riverpod, Provider]*
- **Native Integration:** Native Audio Runtime (C/C++ via FFI/Native Assets) and Android platform layers.

### Layered Structure
1. **UI Layer (`lib/widgets`, `lib/pages`):** Flutter widgets, responsive layouts, and view-related logic.
2. **Domain/Logic Layer (`lib/domain`, `lib/models`):** Pure Dart business logic, interfaces, entities, and state containers.
3. **Data/Service Layer (`lib/services`):** API clients, local database integration, native bindings, and repository implementations.

---

## 2. Coding Conventions & Style Guides

### Dart & Flutter Best Practices
- **Type Safety:** Always declare types explicitly for public APIs, function parameters, and return types. Avoid dynamic types where possible.
- **Linter & Analyzer:** Adhere strictly to rules in `analysis_options.yaml`. Never bypass or suppress analyzer warnings.
- **Immutability:** Use immutable data structures (`@immutable` classes, final fields) and copy-with patterns.
- **Composition over Inheritance:** Prefer wrapping and delegating over deeply nested class hierarchies.

### Native Code Standards (C/C++ & Kotlin)
- **Memory Management:** Ensure any allocated memory in C/C++ is cleanly freed on the Dart side or via registered finalizers.
- **FFI Bindings:** Prefer using auto-generated FFI bindings via `package:ffigen` configuration in `ffigen.yaml` over manually written bindings.

---

## 3. Core Workflows & Commands

### Setup & Dependencies
- Get dependencies: `flutter pub get`
- Generate code (FFI/JSON serializable/Mocks): `dart run build_runner build --delete-conflicting-outputs`

### Static Analysis & Formatting
- Run static analyzer: `dart analyze`
- Auto-format code: `dart format .`

### Testing
- Run Unit/Widget tests: `flutter test`
- Run specific test file: `flutter test test/path_to_test.dart`

### Building the Project
- Build Android APK: `./build-apk.sh` or `flutter build apk --release`

---

## 4. Testing & Verification Requirements

- **Unit Testing:** Write unit tests for all domain models, services, and complex business logic in the `test/` directory.
- **Widget Testing:** Verify responsive UI widgets, layout states, and interactions using `WidgetTester`.
- **Mocking:** Use `mockito` or `mocktail` to mock heavy external dependencies (network, databases, native FFI).
- **Validation Mandate:** Before pushing or submitting any PR, all local tests must pass and static analysis must have zero warnings/errors.

---

## 5. Private Notes & Memory Guideline

- For personal configuration, local machine paths, or private workflows, use the **Private Project Memory** directory (`.gemini/tmp/dump/memory/`) instead of committing them here.
