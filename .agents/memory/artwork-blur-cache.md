# Now Playing Artwork Blur Cache

## Scope
- Covers only the `ArtworkBlurPlayerBackground` used by the artwork-blur Now Playing style.
- It does not change the main cover artwork, ArtworkRepository's source cache, artwork decode target (384 px), or WebP quality.

## Rendering path
- Request the artwork through `ArtworkRepository` at the existing 384 px target.
- While a blurred frame is being generated, keep the prior behavior as a visual fallback using `ImageFiltered`.
- Rasterize the blur once with `PictureRecorder` and `ImageFilter.blur`, then display it with `RawImage` so drag/expand animation does not repeatedly apply the full-screen blur filter.
- Scale the pre-blur sigma according to the source-to-viewport scale to preserve the existing on-screen blur appearance (`sigma 32`).

## Memory and lifecycle invariants
- Keep only a small in-memory LRU of at most three generated 384 px frames; never write generated blur frames to disk.
- Cache keys include song identity and effective source blur sigma.
- In-flight work is shared by identical keys; artwork and blur request IDs reject stale results after rapid track changes.
- A lease count keeps a cached `ui.Image` alive while any widget displays it.
- Eviction is deferred until after the current frame so the image is not disposed while an old `RawImage` may still be mounted.
- If artwork loading or blur generation fails or times out, preserve the original `ImageFiltered` fallback.

## Validation
- Changes were committed directly to `wandavenus/Dump` on `main`.
- The Flutter analyzer and device rendering performance still need a run; GitHub source edits alone do not establish a clean build or a measured FPS improvement.
