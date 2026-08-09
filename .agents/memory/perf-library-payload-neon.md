# Perf scope 1.5.20 — library payload, isolate parse, PCM reuse, soft-clip tanh

## B — getSongs payload compact (JSON string)

- **Kotlin** (`MainActivity.kt`): `getSongs()` now returns `String` (JSON) instead
  of `List<Map<String, Any?>>`. Single-pass `songsToJson()` (StringBuilder +
  `JSONObject.quote()` for escaping — no JSONArray/JSONObject churn per song).
  Handler result: `result.success(jsonString)`.
- **Why**: StandardMessageCodec tags every nested map/string/int with per-value
  type markers → for a large library the codec cost on BOTH sides is several
  times the raw data size. One String = one channel message.
- `lastSongRefs`/`MetadataPrescanner` logic unchanged (still built from the
  internal List inside `getSongs()`).
- Dart side contract: `invokeMethod<String>('getSongs')` (was
  `invokeListMethod<dynamic>`).

## G — parse & persist in background isolates (Dart)

- `media_store_service.dart` `_refreshSongsImpl`: live parse now
  `compute(_parseSongsJson, songsJson)` — same helper the warmUp cache path
  already used (single source of truth). Previously the live path mapped
  `LocalSong.fromMap` over the whole library on the UI thread (100–300 ms jank
  on big libraries during refresh/rescan).
- `_parseSongsJson` also carries the old live-path
  `.where((song) => song.path.isNotEmpty)` filter — MediaStore rows without a
  resolvable path must not reach the UI (no-op on cache content, which was
  already filtered when persisted).
- `_persist`: JSON encode moved to `compute(_encodeSongsJson, songs)`
  (new top-level helper). `List<LocalSong>` is isolate-sendable (plain
  object, sendable fields).

## N-3 — PcmDecoder ShortArray reuse

- `PcmDecoder.kt`: grow-only `var chunk = ShortArray(0)` reused across output
  buffers; `sb.get(chunk, 0, remaining)`. MediaCodec output sizes are ~constant
  per track → zero allocation after first chunk.
- Safe with oversized buffer: JNI `nativeAddFramesShort` validates
  `frame_count <= array_len / channels` and only reads `frame_count*channels`
  shorts; `GetShortArrayElements` + `JNI_ABORT` (read-only, no copy-back).

## N-1 — soft clipper fast tanh (only applied item)

- `soft_clipper_processor.c` `_soft_clip`: `tanhf(excess/range)` →
  `_fast_tanh(z) = z>=3 ? 1 : z(27+z²)/(27+9z²)`.
  Properties: tanh(0)=0/deriv 1 (C¹ at threshold), exactly 1.0 at z=3 (so
  clamp at 3 keeps output ≤ 0 dBFS), monotonic, max error ≈ 0.024 vs tanhf in
  the excess region (inaudible).
- **N-1 items checked and NOT applied (audit docs describe older
  implementations — always diff against actual code):**
  - Limiter NEON peak-scan: current code has NO look-ahead window scan; peak
    is per-sample + one-pole release, gain is per-sample stateful → whole-
    buffer `nar_gain_apply_neon` not applicable; 2-ch path already unrolled.
  - Compressor gain-multiply NEON: 2-ch already unrolled (2 mults/frame);
    `logf`/`expf` per frame is the true cost and is unavoidable.
  - Crossfeed stereo-matrix NEON: matrix is 4 mul + 2 add/frame (~5% of
    processor); biquads (dominant cost) are ALREADY NEON via
    `nar_biquad_stereo_neon`; strided matrix loads would be a wash or worse.
  - Crossfeed biquad NEON: already done (neon_kernels.S), do not redo.
- Build wiring: `libnative_audio_runtime.so` is built by the Flutter native
  assets hook (`native_audio_runtime/hook/build.dart`, explicit `sources:`
  list incl. soft_clipper_processor.c + neon_kernels.S) — NOT by Gradle's
  `src/main/cpp/CMakeLists.txt` (that only builds replaygain_native +
  stretch_native).

## Lesson

Audit docs (`docs/Native_Performance_Audit.md`) may describe code that has
since been rewritten (e.g. limiter window-scan, crossfeed biquads). Verify
each "NEON candidate" against the current implementation before applying —
most were already addressed by 2-ch unrolls or existing NEON kernels.
