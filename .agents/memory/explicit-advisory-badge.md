# Explicit advisory badge

## Behavior
- Reads the `ITUNESADVISORY` tag from Media3 `VorbisComment` entries (Opus/Ogg/FLAC) and ID3 `TXXX` custom text frames; the parser also checks a matching mdta key.
- Values `1`, `explicit`, `true`, and `yes` mean explicit. Values `0`, `2`, `clean`, `false`, `no`, `none`, and `not explicit` mean not explicit.
- Only recognized explicit values activate the badge. Other advisory values and successful parses without an advisory are not marked explicit; a failed metadata read returns null and is retried.
- `ExplicitSongTitle` renders `[E]` after the title only for explicit tracks. It is reused for lists, search, playlists, browse cards, queue, mini player, and full player.

## Data flow
1. `TagBuilder` normalizes the advisory tag into nullable `AudioTags.isExplicit`.
2. `MetadataCacheDb` stores explicit status in nullable `is_explicit`, keyed by file path/mtime through the existing metadata cache. Schema v2 adds the column without dropping the existing cache.
3. Native `getExplicitStatus` runs on `metadataExecutor`; Flutter `MediaStoreService` coalesces in-flight requests and memoizes results for the current library snapshot.
4. On a library refresh, the in-memory explicit-status cache is cleared.

## CI regression fix (2026-10-27)
- Noisegraph test-suite run #191 tested Dump commit `6eb8141942a07a21ff390a6f1ca2a883006ab7dd`; `flutter analyze` passed, but the browse-banner golden changed and the wide-player widget test left the 12-second MethodChannel timeout pending.
- `ExplicitSongTitle` now returns a plain `Text` widget when status is not explicit, preserving the original layout and golden pixels; it adds a `Row` only when an `[E]` badge is needed.
- `PlayerContent` defers explicit-status lookup until its mini header is visible, avoiding needless channel work during normal player layout.
- `player_wide_layout_test.dart` mocks `getExplicitStatus`; dedicated widget tests cover both explicit and clean tracks.

## Regression tests
- `TagBuilderTest` covers Vorbis advisory `1`, case-insensitive ID3 TXXX key, non-explicit values `0` and `2`, absent tags, and invalid values.
- Re-validate with native metadata unit tests and `flutter analyze` when the repository toolchain is available.
