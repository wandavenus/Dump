# C++ / JNI / EBU R128 Audit — ReplayGain & Stretch Modules

Scope: all C++ under `android/app/src/main/cpp/` (`replaygain/` and `stretch/`)
plus the Windows/Linux example runner files under `native_audio_runtime/example/`.

Read-only review. No source was modified. Findings grouped by severity
(correctness/safety first), each with `file:line`, the violated best practice,
and a suggested fix. The example-runner files (`win32_window.*`, `flutter_window.*`,
`utils.*`, `main.{cc,cpp}`, `my_application.*`, `resource.h`) are standard
Flutter-generated boilerplate with only minor stylistic issues noted at the end.

---

## HIGH

### H1. `nativeComputeAlbumLoudness` reorders JNI array release vs. lock — use-after-free window if `ReleaseLongArrayElements` semantics change
`replaygain_jni.cpp:271` (inside the locked block at `263`)
```cpp
std::lock_guard<std::mutex> lock(g_registry_mutex);
...
env->ReleaseLongArrayElements(handles, elems, JNI_ABORT);   // line 271
result = replaygain::ComputeAlbumLoudness(states);          // line 272
```
`elems` is released (ABORT — no copy-back, so the pointer is still valid to read
immediately after; for `JNI_ABORT` the buffer is not invalidated) **before**
`ComputeAlbumLoudness` runs. That is actually safe *for this* code path, but the
comment at `255-259` claims the lock is held across the *computation* to prevent a
concurrent `DestroyAnalyzer` free of the `ebur128_state*`. The lock IS held, so
the states are safe — however `ReleaseLongArrayElements` is itself a JNI call that
can throw/block and is pointless to keep inside the mutex. Move the
`ReleaseLongArrayElements` call **outside** the locked block (right after the
`GetLongArrayElements` guard, with a scope), keeping only the map lookup +
`ComputeAlbumLoudness` under the lock. Benefit: shorter critical section and the
comment matches reality.

### H2. `ComputeAlbumLoudness` mutates shared state of still-alive analyzers via `const_cast`
`ebur128_analyzer.cpp:90-91`
```cpp
const int rc = ebur128_loudness_global_multiple(
    const_cast<ebur128_state**>(states.data()), states.size(), &album_loudness);
```
`ebur128_loudness_global_multiple` is a *read* of accumulated loudness, but the
downstream handles are still live (per the contract in `ebur128_analyzer.h:31-33`
the per-track analyzers are kept alive until after album aggregation). In
practice libebur128 does not mutate in that call, but the `const_cast` papers over
the fact that the same `ebur128_state*` objects are later used by
`Finish()/DestroyAnalyzer`. If `ebur128` ever updated internal running state, this
would corrupt per-track results. Suggested fix: store `std::vector<ebur128_state*>`
(already non-const in `replaygain_jni.cpp:260`) and drop the `const_cast` by
having `ComputeAlbumLoudness` take a non-const `vector<ebur128_state*>` (or a
`vector<const ebur128_state*>` only if the API truly is read-only — verify the
lib signature). Also document that album aggregation must occur *before* any of
those handles is `Finish()`ed if `global_multiple` has side effects.

### H3. `RestoreMetadataRegionFd` pread verifies only the first ≤4 bytes
`tag_writer.cpp:559-565`
```cpp
const size_t check_len = std::min(backup.bytes.size(), static_cast<size_t>(4));
unsigned char head[4] = {};
const ssize_t nread = ::pread(fsync_guard.Fd(), head, check_len, 0);
if (nread < 0 || ... != check_len ||
    std::memcmp(head, backup.bytes.data(), check_len) != 0) { ... kWriteFailure; }
```
Only the first 4 bytes are read back to confirm the restore. A partial/shifted
write that differs anywhere beyond byte 4 is not detected, so `Restore` can return
`kOk` for a corrupted region. The comment (`556-558`) justifies this as "enough to
detect a complete no-op I/O failure," but it does **not** detect *wrong* data
beyond byte 4. Suggested fix: verify all `backup.bytes.size()` bytes (the backup is
already bounded to 64 MB by `ReadRegion` at `metadata_region.cpp:213`), or at least
verify a trailing chunk as well as the head. At minimum, the comment must not claim
it detects "wrong data" generally.

### H4. `WriteReplayGainTagsFd` / `RemoveReplayGainTagsFd` — fd double-close / ownership confusion on the `kUnknown` backup-failure path
`tag_writer.cpp:256-263` (write) and `330-337` (remove)
```cpp
if (out_region != nullptr) {
    const WriteResult backup_result = BackupRegion(fd, req.format, out_region);
    if (backup_result != WriteResult::kOk) {
        ::close(fd);                 // <-- caller-owns fd, closed here
        return backup_result;
    }
}
```
`BackupRegion` only reads via `pread` (`metadata_region.cpp:200-217`); it never
takes ownership of `fd`. So closing `fd` here is correct *only because* of the
documented contract that `WriteReplayGainTagsFd` does NOT close `fd`. But note the
asymmetry: on the `stream.isOpen()` failure path (`267-272`) `fd` is also closed,
yet on every other return path `fd` is **not** closed, leaving ownership with the
caller. This mixed ownership (sometimes native closes, sometimes caller) is a
double-free/leak hazard if any future path forgets. Suggested fix: make ownership
explicit and uniform — either (a) the caller always closes `fd` and native never
closes it (remove the three `::close(fd)` calls), or (b) adopt RAII `unique_fd` so
the close is provably single. The pre-existing `FsyncGuard` already dup's the fd
for sync, so a `unique_fd` wrapper around `fd` is the cleanest.

---

## MEDIUM

### M1. `gProcClass` global JNI reference is never deleted (process-exit leak)
`stretch_jni.cpp:77, 98, 101`
`gProcClass` is a `NewGlobalRef` created lazily and cached for the process
lifetime; it is never `DeleteGlobalRef`'d. On Android this is commonly tolerated
(torn down at process exit), but combined with `gLogMethodId` it is a genuine
permanent global-ref leak if the library is ever `dlclose`d or the class loader
replaced (e.g. on some hot-restart / multiple-classloader scenarios). Suggested
fix: provide a `JNI_OnUnload` that `DeleteGlobalRef(gProcClass)` and nulls both
pointers, or manage them via a `std::call_once` + `atexit`/`JNI_OnUnload`.
(Note: refs created in `bridgeToSystemLog` local refs `jLevel/jMessage` are
correctly released at `111-112`.)

### M2. `stretch_jni.cpp` uses `jclass` (not `jobject`) as the second arg of
native methods but the comment/usage implies instance methods
`stretch_jni.cpp:188, 227, 233, ...` — `JNIEnv *env, jclass, jlong ...`
All `SignalsmithStretchAudioProcessor_*` entry points declare `jclass` (static
native). `nativeLog` is indeed a `@JvmStatic` (`stretch_jni.cpp:101` `(Ljava/lang/String;Ljava/lang/String;)V` static). This is consistent. No bug — but note
`bridgeToSystemLog` resolves the class by name every first call; if the class is
unavailable it silently disables logging (`95-97`). That is acceptable fail-open
behavior; just ensure the `ExceptionClear()` at `95`/`102` is reached on *every*
`FindClass`/`GetStaticMethodID` failure (it is). Low risk, listed for completeness.

### M3. `JStringToStd` may silently truncate/ mangle on `Modified UTF-8`
`jni_common.h:25-32`
`GetStringUTFChars` returns **Modified UTF-8** (not standard UTF-8): embedded NULs
and supplementary chars are encoded differently. `std::string` built from it
(`std::string result(chars)`) stops at the first embedded NUL and mis-represents
supplementary characters. For tag title/artist/album values this can truncate
legitimate strings containing a NUL (rare but possible from malformed files) or
mangle emoji/supplementary-plane characters. Suggested fix: use
`GetStringUTFRegion`+`env->GetStringUTFLength`, or `GetStringChars` (UTF-16) +
`env->NewString` semantics; store as `std::u16string` or convert with
`ConvertJavaStringToUTF8` style logic. At minimum document the Modified-UTF-8
limitation.

### M4. `UnpackSnapshot` / `PackSnapshot` assume exactly `kSnapshotFieldCount == 9`
`replaygain_jni.cpp:41, 52-56, 73-77`
The order of the 9 fields is duplicated in two places (pack and unpack) and must
stay in sync with `ReplayGainNative.kt`. There is no compile-time link. A missing
or extra field in Kotlin silently mis-binds entries. Suggested fix: generate the
mapping from a single source (a shared constant list) or assert array length == 9
everywhere (note `UnpackSnapshot` only checks `>= 9` at `72`, and `PackSnapshot`
relies on the caller). Low impact but a real maintenance trap.

### M5. `ReadTxxx` returns `std::string()` for "field present but empty" vs `nullopt` for "absent"
`tag_writer.cpp:83-84` (also `ReadXiphField` `113` returns `nullopt` consistently)
```cpp
if (fields.size() < 2) return std::string();   // present-but-empty
```
This is internally inconsistent: Xiph returns `nullopt` for empty/missing while
ID3v2 returns an empty `std::string` (treated as `has_value()` ⇒ "present"). The
verification path `GainMatches`/`PeakMatches` (`142-150`) compares `*actual ==
FormatGainDb(...)`, so an empty-but-present TXXX frame would fail verification
differently from an empty Xiph field. Suggested fix: make both return `nullopt`
when there is no usable value, so "absent" is represented uniformly.

### M6. `DetermineFlacRegionSize` integer overflow on crafted `block_len`
`metadata_region.cpp:70-73`
```cpp
const int64_t block_len = (bh[1] << 16) | (bh[2] << 8) | bh[3];  // up to 2^24-1
offset += 4 + block_len;
```
`offset` is `int64_t` so a single block can't overflow, but a long chain of
~16 MB blocks (allowed by the 4096-iteration guard at `64`) drives `offset` toward
`4096 * 16MiB ≈ 64 GiB` — far beyond any real file. `offset` is only used as a
`pread` argument and as the return value, so it won't overflow `int64_t`, but the
returned "region size" can be absurd (returned as the metadata region and then
capped to 64 MiB by `ReadRegion` at `213`). That cap saves the allocator, but the
region *determination* still returns a wrong (huge) size for a malicious file,
causing `ReadRegion` to return `false` (→ `kUnknown` → skip) — acceptable, but the
intermediate `offset` arithmetic deserves a sanity cap (e.g. reject if
`offset > kMaxSafeRegionBytes`). Suggested fix: bail with `nullopt` once
`offset > kMaxSafeRegionBytes`.

### M7. `DetermineOggHeaderRegionSize` 200000-page loop worst case
`metadata_region.cpp:132`
`for (int guard = 0; guard < 200000; guard++)` — each iteration does two `pread`s.
200k iterations is bounded but a hostile file could force ~400k syscall reads
before bailing. Combined with `ReadRegion`'s 64 MB cap it's not an OOM, but it is a
CPU/IO DoS. 200000 pages × 255 bytes ≈ 50 MiB of potential header, which exceeds
the 64 MB region cap anyway. Suggested fix: add an `offset > kMaxSafeRegionBytes`
early-out like the FLAC path.

### M8. `nativeDestroyAnalyzer` accepts arbitrary `jlong` and `erase`s without validation
`replaygain_jni.cpp:238-242` → `DestroyAnalyzer` `168-171`
`DestroyAnalyzer` does `g_registry.erase(handle)`. If Kotlin passes a stale/wrong
handle it simply no-ops (safe). But a **double** `nativeDestroyAnalyzer` call on
the same handle with the analyzer already `Finish()`ed elsewhere is fine. The real
risk: a handle value of `0` returned on creation failure (`replaygain_jni.cpp:182,
185`) is also a valid `erase` no-op, so Kotlin must never destroy `0`. This is
documented (`10-15`) and acceptable, but consider asserting/returning and logging
on an unregistered handle to surface Kotlin-side bugs.

---

## LOW

### L1. Header guards use `#ifndef X_H` not `#pragma once`
`ebur128_analyzer.h`, `tag_writer.h`, `metadata_region.h`, `jni_common.h`, and the
runner headers (`win32_window.h`, `flutter_window.h`, `utils.h`,
`my_application.h`, `resource.h`) all use classic include guards. Modern C++17
compilers universally support `#pragma once`, which is less error-prone (no
guard-symbol collisions). Suggested fix: adopt `#pragma once` (or keep guards but
ensure symbol uniqueness — they currently are unique).

### L2. `EburAnalyzer::Create` uses bare `new` instead of `make_unique`
`ebur128_analyzer.cpp:37`
```cpp
return std::unique_ptr<EburAnalyzer>(new EburAnalyzer(state, channels));
```
Prefer `std::make_unique<EburAnalyzer>(state, channels)` (no raw `new`, exception-
safe). The raw `new` is fine here but inconsistent with modern style. Same pattern
is acceptable in `stretch_jni.cpp:195` only because a `std::nothrow` placement is
used (`new (std::nothrow)`), which `make_unique` can't express — keep that one.

### L3. `const` on `BuildWriteRequest` parameters is on the value, not the type
`replaygain_jni.cpp:88-92` and `ebur128_analyzer.h` helpers — `jdouble
track_gain_db` etc. are passed by value; the `const` qualifier does nothing
useful. Minor; drop the redundant `const` on by-value params or leave for local
clarity. Low priority.

### L4. `ebur128_analyzer.cpp` `Finish()` returns `result` with default-initialized
fields when `ebur128_loudness_global` fails
`ebur128_analyzer.cpp:54-57`
```cpp
double integrated = -HUGE_VAL;
if (ebur128_loudness_global(...) != EBUR128_SUCCESS) return result;  // result.valid = false
```
`result.integrated_lufs` defaults to `-HUGE_VAL` (from the struct default at
`ebur128_analyzer.h:16`) and `valid = false`. Good. But note `recommended_gain_db`
remains `0.0` here while `LufsToReplayGainDb` would return `0.0` for non-finite
(`96-99`) anyway — consistent. No bug; just confirm Kotlin treats `valid==false`
before using `recommended_gain_db`. (Kotlin side, out of scope.)

### L5. `EburAnalyzer::Finish` comment claims idempotency contradicted by `AddFramesShort` doc
`ebur128_analyzer.h:54-56` vs `:49` — `Finish()` says "Safe to call multiple
times (idempotent)" but libebur128 state keeps accumulating after `Finish()`, so a
second `Finish()` on a handle that later received more frames would yield a
*different* result. "Idempotent" is misleading; say "may be called more than once;
subsequent AddFrames still accumulate." Documentation fix only.

### L6. `tag_writer.cpp` `FormatPeak` mixes clamp semantics with `FormatGainDb`
`tag_writer.cpp:43-50`
`FormatPeak` clamps negative to 0 (`std::max(0.0, peak_linear)`) but leaves values
>1.0. For sample/true peaks that's correct (true peak can exceed 1.0). However the
comparison in `PeakMatches` (`145-147`) re-formats the request with the same
function, so it's self-consistent. No bug; just note the asymmetry vs. ReplayGain
spec where peak should be ≥ 0.

### L7. `g_next_handle` starts at 1 and never reclaims; `jlong` handle space
`replaygain_jni.cpp:153, 157`
Handles start at 1 and increment forever; for a long-running process doing
millions of scans this could (theoretically) wrap `jlong`. Practically unreachable,
but a `jlong` vs `int64_t` cast (`g_next_handle++` is `jlong`) is fine. No fix
needed; noted for completeness.

### L8. Windows runner: singleton `WindowClassRegistrar` leaks its instance_
`win32_window.cpp:64-69, 87`
`WindowClassRegistrar::instance_` is `new`'d lazily and never deleted (the window
class is unregistered at `109-112` but the registrar object leaks). Standard
Flutter boilerplate — acceptable (lives for process lifetime), but could be a
`static WindowClassRegistrar instance;` (Meyers singleton) to avoid the leak and
the `new`/leak. Low priority.

### L9. Windows runner: `CreateAndAttachConsole` ignores return of `_dup2`
`utils.cpp:14, 17`
```cpp
if (freopen_s(&unused, "CONOUT$", "w", stdout)) { _dup2(_fileno(stdout), 1); }
```
The `_dup2` is inside the `if (freopen_s(...) != 0)` branch, meaning it only runs
when `freopen_s` *fails* — likely the opposite of intent (you'd dup on success).
Also `unused` is written but never read (compiler warning). Suggested fix: run
`_dup2` after a successful `freopen_s`, and mark `unused` with
`(void)unused;` / remove the variable. Minor but a logic smell.

### L10. Windows runner: `main.cpp` ignores `CoInitializeEx` return value
`main.cpp:18`
`::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);` return value is unchecked.
If COM already initialized in a different threading model, this returns
`S_FALSE`/`RPC_E_CHANGED_MODE` and the subsequent Flutter/plugin COM usage may
misbehave. Suggested fix: check the `HRESULT` and log `S_FALSE` at minimum.

### L11. Linux runner: `my_application_local_command_line` does not free the original `argv`
`my_application.cc:87`
`self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);` and later
`g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev)` in `dispose`
(`123`) — correctly freed. No leak. The `g_strdupv(*arguments + 1)` copies but
does not free the source `*arguments` (that's owned by GLib and freed by GLib).
Correct. No fix.

### L12. `stretch_jni.cpp` `ensureCapacity` pointer recomputation is correct but
relying on `inPtrs.size()` sentinel
`stretch_jni.cpp:162-175`
The planar pointers are correctly recomputed from `inFlat.data()` each call using
the *current* frame counts, so no stale aliasing (good, matches the comment at
`154-156`). However `inPtrs`/`outPtrs` are resized based on `channels` while
`inFlat`/`outFlat` grow by `channels * frames`. If a call passes `frames == 0`
(e.g. `nativeFlush` at `486` calls `ensureCapacity(0, outputFrames)`), `inFlat` is
not grown — fine because input isn't used in flush. Consistent.

### L13. Missing `#include <cstdint>` / `<cstddef>` where fixed-width types used
`stretch_jni.cpp` uses `intptr_t` (`179`) — relies on it being pulled in transitively
via `<jni.h>`/`<cstdint>`. On some toolchains `intptr_t` requires `<cstdint>`.
`metadata_region.cpp` relies on `<cstdint>` via `metadata_region.h`. Add explicit
`<cstdint>` where `intptr_t`/`uint8_t`/`int64_t` are used to satisfy "include what
you use." Low priority.

### L14. `nativeProcess` reads `outSamples` with no bounds check against the Java
direct buffer capacity
`stretch_jni.cpp:339-348`
`outSamples[i * h->channels + c]` is written for `outputFrames * channels` floats,
trusting the Kotlin side allocated a large-enough direct `ByteBuffer`. A mismatch
(Java allocates fewer frames than it tells native) is an out-of-bounds write into
the native buffer → potential SIGSEGV / memory corruption. This is inherent to the
direct-buffer JNI contract, but the code does no validation. Suggested fix: query
the buffer capacity via `env->GetDirectBufferCapacity(outputBuffer)` and reject if
`< outputFrames * channels` (return -1). This is a real safety gap on the audio
thread — consider promoting to MEDIUM.

---

## EBU R128 / libebur128 math correctness notes

- `ebur128_analyzer.cpp:28-32` enables `EBUR128_MODE_I | LRA | TRUE_PEAK |
  SAMPLE_PEAK | HISTOGRAM`. For TRUE_PEAK libebur128 requires the proper mode;
  correctly included. Good.
- Channel weighting: libebur128 handles ITU-R BS.1770 channel weighting internally
  given the channel count; the code passes `channels` (1-8, validated at `26`) to
  `ebur128_init`. Correct. Note: libebur128 does **not** auto-assign channel roles
  (LFE, center) from a raw channel count — a 6-channel input is assumed to be a
  specific layout. If Kotlin ever feeds, e.g., 5.1 with an LFE, libebur128 treats
  all channels equally unless `ebur128_set_channel` is called. The current code
  never calls `ebur128_set_channel`, so LFE/center weighting per BS.1770-4 is **not**
  applied. If the app intends spec-compliant loudness for multichannel, this is a
  correctness gap (MEDIUM for multichannel correctness). Suggested fix: after
  `ebur128_init`, call `ebur128_set_channel(state, ch, EBUR128_*_TYPE)` for each
  channel according to the known layout.
- `true_peak_dbtp`/`sample_peak_dbfs` take the **max across channels**
  (`64-75`). EBU R128 reports per-channel max true peak; reporting the global max
  is a reasonable choice but loses per-channel info. Documented as "Max true peak
  across channels" — acceptable.
- `LufsToR128Q7_8` (`101-111`): uses `std::lround(gain_db * 256.0)` and clamps to
  int16. Correct Q7.8 quantization, reference -23 LUFS matches Opus R128. Good.
  Edge: `std::lround` returns `long`; clamping to ±32768 then `static_cast<int32_t>`
  is safe.
- `lra` (`59-60`) is taken even if `ebur128_loudness_range` returns non-success;
  left at `0.0` default — acceptable (non-fatal per comment).
- `ComputeAlbumLoudness` uses `ebur128_loudness_global_multiple` — correct ITU-R
  BS.1770-4 album aggregation (gate + average), not simple concatenation. Good.

---

## Summary

| Sev | Count | Headlines |
|-----|-------|-----------|
| HIGH | 4 | fd ownership/close confusion (H4), weak restore verification (H3), `const_cast` over shared live state (H2), misleading lock/release comment (H1) |
| MED | 8 | global JNI ref leak (M1), Modified-UTF8 truncation (M3), inconsistent empty-field semantics (M5), region-size DoS/overflow guards (M6/M7), snapshot-field sync trap (M4/M8) |
| LOW | 14 | guard style, `make_unique`, doc/comment accuracy, runner boilerplate leaks, unchecked COM init, direct-buffer capacity (L14 → consider MED), include-what-you-use |

Top priorities: H4 (fd ownership — leak/double-close risk), H3 (restore
verification only checks 4 bytes), M1 (global JNI ref never released), L14 (no
direct-buffer capacity check → OOB write on audio thread), and the EBU R128
channel-role gap (no `ebur128_set_channel`).
