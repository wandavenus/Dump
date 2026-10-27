# Explicit advisory badge

## Behavior
- Reads the `ITUNESADVISORY` tag from Media3 `VorbisComment` entries (Opus/Ogg/FLAC) and ID3 `TXXX` custom text frames; the parser also checks a matching mdta key.
- Values `1`, `explicit`, `true`, and `yes` mean explicit. Values `0`, `2`, `clean`, `false`, `no`, `none`, and `not explicit` mean not explicit.
- Unknown advisory values remain unknown. A successful metadata parse with no advisory is treated as non-explicit; a failed metadata read returns null and does not persist a result.
- `ExplicitSongTitle` renders `[E]` after the title only for explicit tracks. It is reused for lists, search, playlists, browse cards, queue, mini player, and full player.

## Data flow
1. `TagBuilder` normalizes the advisory tag into nullable `AudioTags.isExplicit`.
2. `MetadataCacheDb` stores explicit status in nullable `is_explicit`, keyed by file path/mtime through the existing metadata cache. Schema v2 adds the column without dropping the existing cache.
3. Native `getExplicitStatus` runs on `metadataExecutor`; Flutter `MediaStoreService` coalesces in-flight requests and memoizes results for the current library snapshot.
4. On a library refresh, the in-memory explicit-status cache is cleared.

## Regression tests
- `TagBuilderTest` covers Vorbis advisory `1`, case-insensitive ID3 TXXX key, non-explicit values `0` and `2`, absent tags, and invalid values.
- Re-validate with native metadata unit tests and `flutter analyze` when the repository toolchain is available.
