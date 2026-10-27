# Explicit advisory badge

## Behavior
- Reads the `ITUNESADVISORY` tag from Media3 `VorbisComment` entries (Opus/Ogg/FLAC) and ID3 `TXXX` custom text frames; the parser also checks a matching mdta key.
- Values `1`, `explicit`, `true`, and `yes` mean explicit. Values `0`, `2`, `clean`, `false`, `no`, `none`, and `not explicit` mean not explicit.
- Only recognized explicit values activate the badge. Other advisory values and successful parses without an advisory are not marked explicit; a failed metadata read returns null and is retried.
- `ExplicitSongTitle` renders the shared `ExplicitAdvisoryBadge` after a title only for explicit tracks. The badge is a square borderless white surface at 18% opacity; the E is cut out with `BlendMode.dstOut`. The complete badge is now 5% smaller than its previous size (76.95% of the original derived dimensions), with a 2.31 px corner radius.
- The shared `ExplicitAdvisoryBadge` is also used by the mini header inside `PlayerContent` when the lyrics/queue overlay is visible. Do not add a separate text-only `[E]` marker there.
- The shared badge is used in lists, search, playlists, browse cards, queue, mini player, full player, and song context menu.

## Data flow
1. `TagBuilder` normalizes the advisory tag into nullable `AudioTags.isExplicit`.
2. `MetadataCacheDb` stores explicit status in nullable `is_explicit`, keyed by file path/mtime through the existing metadata cache. Schema v2 adds the column without dropping the existing cache.
3. Native `getExplicitStatus` runs on `metadataExecutor`; Flutter `MediaStoreService` coalesces in-flight requests and memoizes results for the current library snapshot.
4. On a library refresh, the in-memory explicit-status cache is cleared.

## CI regression fix (2026-10-27)
- Noisegraph test-suite run #191 tested Dump commit `6eb8141942a07a21ff390a6f1ca2a883006ab7dd`; `flutter analyze` passed, but the browse-banner golden changed and the wide-player widget test left the 12-second MethodChannel timeout pending.
- `ExplicitSongTitle` returns a plain `Text` widget when status is not explicit, preserving the original layout and golden pixels; it adds a `Row` only when an `[E]` badge is needed.
- `PlayerContent` defers explicit-status lookup until its mini header is actually visible, avoiding needless channel work during normal player layout.
- `player_wide_layout_test.dart` mocks `getExplicitStatus`; widget tests cover explicit and clean tracks. The mini-header regression test requires the shared knockout badge and rejects the legacy text-only `[E]`.

## Regression tests
- `TagBuilderTest` covers Vorbis advisory `1`, case-insensitive ID3 TXXX key, non-explicit values `0` and `2`, absent tags, and invalid values.
- Re-validate with native metadata unit tests and `flutter analyze` when the repository toolchain is available.
