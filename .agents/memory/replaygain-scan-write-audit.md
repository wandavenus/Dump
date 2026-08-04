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