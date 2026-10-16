# Now Playing Artwork Blur Cache

## Scope
- Covers only `ArtworkBlurPlayerBackground`, used by the artwork-blur Now Playing style.
- It does not change the main cover artwork, ArtworkRepository's source cache, artwork decode target (384 px), or WebP quality.

## Rendering path
- When the artwork-blur background style is selected, `UnifiedMorphPlayer` schedules a prewarm after the current frame while the player is still collapsed. It is deduplicated by song and viewport size.
- The prewarm resolves artwork through `ArtworkRepository` at the existing 384 px target.
- Blur is rasterized once with `PictureRecorder` and `ImageFilter.blur`, then displayed with `RawImage` so the opening/drag animation can reuse the already-blurred image instead of repeatedly applying a full-screen filter.
- The pre-blur sigma is scaled by the source-to-viewport size to preserve the current on-screen blur appearance (`sigma 32`).
- While a new blurred frame is being generated, retain the existing `ImageFiltered` rendering as a visual fallback.

## Memory and lifecycle invariants
- Keep a small memory-only LRU of at most three generated frames; never write generated blur frames to disk.
- Cache keys include song identity and effective source blur sigma.
- In-flight work is shared by identical keys; separate artwork/blur request IDs reject stale completions after rapid track changes.
- Lease counts keep a cached `ui.Image` alive while widgets display it.
- Eviction is deferred until after the current frame so disposal cannot race with an old `RawImage` still being mounted.
- Failed or timed-out prewarm/rendering falls back to the original runtime blur; it must not block playback or the player UI.

## Validation
- Source changes are committed directly to `wandavenus/Dump` on `main`.
- Flutter analysis, test execution, and device-level FPS/memory measurements remain unverified; source edits alone do not establish a clean build or measured performance gain.
