---
name: Web preview blank white screen — startup Future.wait rethrow
description: BootTrace.step rethrows exceptions from parallel startup warm-up tasks; a web-only MissingPluginException in one of them aborts main() before runApp(), producing a permanently blank white page (no crash, no error visible in preview).
---

## Symptom
Web preview (`build/web/` served by `server.js`) shows a blank white page indefinitely. Browser console shows normal `[BOOT +Nms]` trace lines up through the parallel warm-up `Future.wait([...])` in `main()`, then goes silent — no `AFTER Future.wait`, no `runApp()` reached.

## Root cause
`BootTrace.step()` (see `lib/services/boot_trace.dart`) logs then **rethrows** any exception from the wrapped step. `ArtworkRepository.warmUp()` called `path_provider`'s `getApplicationSupportDirectory()` with no `kIsWeb` guard — on the web platform this throws `MissingPluginException` (no `dart:io`/path_provider implementation there). Since `warmUp()` is one of several futures in the top-level `Future.wait([...])` in `main()` (not individually try/caught), the rethrown exception propagates out of the `Future.wait`, is never caught locally, and is swallowed by `runZonedGuarded`'s error handler — so `main()` never reaches `runApp()`. No crash, no visible error, just a permanently blank page.

**Why this matters:** any new disk/platform-channel-backed warm-up step added to that startup `Future.wait` array must be web-safe (skip via `kIsWeb` or catch the platform's MissingPluginException) — otherwise it silently blanks the entire web preview with no diagnostic other than reading the BOOT trace.

**How to apply:** when adding a warm-up/init step to the parallel startup batch in `main()`, either (a) guard the whole body with `if (kIsWeb) return;` when the feature is disk/native-only, or (b) wrap the risky call in its own try/catch — don't rely on the outer `Future.wait` catching it, since `BootTrace.step` deliberately rethrows for diagnostics. If the web preview ever goes blank again, read the BOOT trace first: whichever step's `EXIT`/`EXCEPTION` line never appears is the culprit.
