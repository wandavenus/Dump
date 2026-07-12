---
name: Native runtime extern symbol name mismatch
description: dlopen "cannot locate symbol" pattern caused by a .c file defining a differently-named static function instead of the extern symbol its own header promises.
---

## Pattern
`native_audio_runtime_internal.h` declares an extern-linkage function as "defined
once in native_audio_runtime.c". If that .c file never includes its own internal
header, the compiler can't check the signature — it's free to define a
similarly-purposed but differently-named `static` helper instead, and nothing at
compile time catches the mismatch. Every other .c file in the same shared library
that includes the internal header and calls the *declared* name compiles fine
(it's just an extern declaration), but the symbol is never actually defined
anywhere in the library. Because shared-library linking doesn't require every
extern reference to resolve (that's deferred to runtime), this surfaces only as
`dlopen: cannot locate symbol <name>` on the target device, not as a build error.

**Why:** whichever .c file is supposed to own a cross-TU internal symbol must
`#include` that symbol's own declaring header, so the compiler checks the
definition against the declaration instead of silently allowing a same-purpose,
differently-named static function to satisfy nothing.

**How to apply:** when auditing a "missing native symbol" dlopen failure, check
first whether the file that's supposed to define it actually includes the header
that declares it — a mismatch there means zero compile-time signal, only a
runtime one.

## Dart-side note (unrelated bug, audited same session)
`num.clamp(lo, hi)` in Dart is NaN/Infinity-safe: `Comparable.compareTo` sorts
NaN as greater than everything, so `nan.clamp(lo, hi)` and
`double.infinity.clamp(lo, hi)` both return `hi`. Any `.clamp(...).toInt()` /
`.clamp(...).round()` chain is therefore already safe from the "Infinity or NaN
toInt" crash — audit bare (unclamped) `.toInt()/.round()/.floor()/.ceil()` calls
on platform-channel/stream doubles instead; that boundary (native tick → Dart
`Duration`) is the real risk, not the many already-clamped UI slider/DSP-param
conversions.
