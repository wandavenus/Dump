# FFmpeg JNI hardening

This PR hardens the local Media3 FFmpeg decoder introduced in Phase 9.

## Review checklist

- [ ] Invalidate native static-library caches whenever the FFmpeg tag, Android API, NDK/compiler, ABI, decoder set, or configure options change.
- [ ] Make Gradle's up-to-date checks include native build configuration and toolchain inputs.
- [ ] Ensure the decoder capability map advertises only codecs present in the configured native build.
- [ ] Include accurate FFmpeg LGPL notices and a reproducible source reference in distributable artifacts; do not represent this as legal approval.
- [ ] Make CI install the pinned NDK and exercise the native decoder build on pull requests.
- [ ] Keep device-only playback verification explicitly separate from CI results.

## Scope

This module is a Media3 audio decoder integration, not a general FFmpeg CLI, demuxer, filter graph, or Automix analysis engine.
