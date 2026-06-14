# Codex Setup

## Project
Flutter music player app.

## Tech Stack
- Flutter
- Dart
- Android (Kotlin)
- Material 3
- just_audio
- audio_service
- audio_session
- provider

## Rules

### Code Style
- Follow existing architecture.
- Reuse existing services before creating new ones.
- Avoid unnecessary dependencies.
- Keep changes minimal and focused.
- Preserve current UI/UX unless explicitly requested.

### Audio System
- Do not replace audio engine without approval.
- Keep compatibility with:
  - just_audio
  - audio_service
  - audio_session
- Do not remove existing playback, queue, lyrics, equalizer, or background audio features.

### Performance
- Minimize widget rebuilds.
- Prefer const constructors.
- Avoid unnecessary setState calls.
- Use ValueNotifier/Provider patterns already present in the codebase.

### Android
- Preserve package name.
- Preserve MainActivity configuration.
- Do not modify ProGuard, Gradle, Manifest, or permissions unless required.

### Git
- Never force-push.
- Never rewrite commit history.
- Create small focused commits.

### Before Finishing
Run:

```bash
flutter pub get
flutter analyze
```

Fix all errors introduced by the change.

Warnings may remain only if they already existed before the task.

### When Unsure
Search the repository first before creating new files, services, themes, models, or utilities.
Prefer existing implementations.

IMPORTANT:
- Never refactor large portions of the repository unless explicitly requested.
- Never create duplicate audio services.
- Always inspect existing files before implementing new functionality.
- Prefer editing existing code over creating new abstractions.
