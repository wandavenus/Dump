---
name: ReplayGain scan/write audit invariants
description: Non-obvious safety rules for the offline scan-to-tag workflow.
---

The offline ReplayGain workflow must treat every scan result as provisional until
the target file identity is revalidated at write time. A `path` used to choose
the tag format and a `songId` used to open the MediaStore fd are separate
identities and must not silently drift.

**Why:** scanning and writing are separate asynchronous operations; a file can
change, move, or be replaced between them, and a successful tag write can then
persist a measurement for different audio.

**How to apply:** carry a file fingerprint (at minimum size + mtime, preferably
an audio/content hash) from scan to write and reject stale measurements.

After a metadata mutation begins, any subsequent failure must be considered
potentially dirty until the exact metadata backup is restored or a fresh
verification proves the file is correct. Returning immediately on `save()`
failure or failed reopen is not equivalent to rollback.

**Why:** fd-based MediaStore writes cannot use an atomic path rename, so the
pre-write region backup is the recovery boundary.

**How to apply:** centralize post-mutation failure handling, attempt restore on
every failure after backup creation, and expose rollback failure separately.

Numeric ReplayGain values crossing Kotlin/Dart/native boundaries must use
locale-independent formatting and finite-value validation. Optional cache fields
must be explicitly removed when a new result has no value.

**Why:** device locale can create comma decimals that Dart parses partially, and
SharedPreferences can otherwise retain a peak from an older scan.

**How to apply:** use `Locale.ROOT`, reject NaN/infinity, and clear stale
optional keys during persistence.

Library-wide scans are compute/cache-only by default; permanent tag mutation must
be an explicit user action with a fresh fingerprint check.

**Why:** a scan is naturally non-destructive, while silently rewriting every
music file creates an avoidable data-loss and permission surprise.

**How to apply:** keep `scanLibrary()`'s default `writeTags` false and do not
enable it from a generic “scan library” button.

---

## RG-01 (2026-08-11) — cache poisoning + UI-unreachable write path

**Findings:**
1. `ReplayGainBridge.scanTrack`/`scanAlbum` cached scan results with a mtime
   captured AFTER decoding — a file replaced mid-scan got its stale measurement
   cached under the NEW mtime, poisoning SQLite (`getReplayGainTags`) until the
   file changed again. Dart `_scanTrackResult` already had a before/after guard;
   the Kotlin cache write did not, and `scanAlbum` had no guard anywhere.
2. The entire native TagLib write path (`writeReplayGain(Batch)`, `scanAlbum`,
   `removeReplayGainTags`, `MediaStoreWriteGate`) had ZERO UI callers —
   `scanLibrary()` was the only entry and always ran with `writeTags: false`.

**Fixes:**
- `ReplayGainBridge` captures mtime BEFORE each scan and skips the cache write
  when the file changed mid-scan (result is still returned; Dart's identity
  guard decides). Same guard added to Dart `scanAlbum` (cache only when
  before/after identity matches).
- F1 UI reachability: (a) Scan Library section gained an explicit
  “Write Tags to Files” toggle → `scanLibrary(writeTags: true)`;
  (b) Song Info sheet gained Write/Remove ReplayGain tag actions
  (`scanOneSong(writeTags: true)` / `removeReplayGainTags`);
  (c) Album page gained “Scan & Write Album Gain” → new
  `ReplayGainService.scanAlbumAndWriteTags()` (before-identities → scanAlbum →
  batch pre-auth → per-track write with album gain, STALE_SCAN-guarded per
  track, per-song failure isolation). New l10n keys `rg*` (en+id, regenerated).

**How to apply next time:** any future scan+cache or scan+write orchestration
must snapshot the file identity before the scan and re-check it before caching
or mutating; never key a fresh cache row on a post-scan mtime alone.