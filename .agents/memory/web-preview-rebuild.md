---
name: Web preview rebuild + audit false positives
description: server.js serves a static prebuilt build/web/; Dart source edits are invisible until rebuilt. Also tracks confirmed false-positive findings from the performance audit.
---

## Web preview requires manual rebuild
`server.js` on port 5000 only serves the pre-compiled `build/web/` directory. Editing files under `lib/` has **no visible effect** in the preview until you run:

```
flutter build web --release --base-href /
```
then restart the workflow.

**Why:** After a batch of Dart edits during a performance-fix pass, the web preview showed a blank white screen. It looked like a regression from the new code, but it was actually just the stale prebuilt JS bundle being served. Rebuilding fixed it immediately.

**How to apply:** Any time you change `lib/` (or other Dart source) and need to verify visually via the web preview, rebuild `build/web/` first — don't trust the preview to reflect source changes automatically. Also note: a single transient blank-white screenshot right after a workflow restart can just be the service-worker install race, not a real bug — take a second screenshot a few seconds later before concluding something is broken.

## Confirmed audit false positives (don't re-"fix" these)
- `music_list/state.dart` and `artist_list.dart` `ScrollController`s: already disposed correctly.
- `noisyReceiver` in `Media3PlaybackService.kt`: IS unregistered, via `ServiceShutdownCoordinator.unregisterReceivers` lambda called from `performTeardown()` in `onDestroy()`. An audit pass flagged it as a leak by only reading the registration site, not the shutdown coordinator.

**Why this matters:** always re-verify an audit/lint finding against the *current* full code path (including indirection through helper/coordinator classes) before spending effort "fixing" something that's already correct.
