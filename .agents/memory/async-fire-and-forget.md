---
name: Async fire-and-forget patterns
description: Pola yang benar untuk menangani Future yang sengaja tidak di-await di Dart/Flutter.
---

## Aturan

1. **Future non-nullable di void function** → `unawaited(expr)`
   - Contoh: `unawaited(_load())` di `initState()`, `unawaited(AudioService.seek(pos))`
   - Butuh import `dart:async` (atau dari parent library file jika ini adalah `part` file)

2. **Future nullable (dari `?.` operator)** → `(expr)?.ignore()`
   - Contoh: `(_formatSub?.cancel())?.ignore()` di `dispose()`
   - `Future.ignore()` ada sejak Dart 2.15, returns `void`

3. **Navigator.push / showModalBottomSheet** di void callback → `unawaited(...)`
   - Ini fire-and-forget yang normal; `unawaited` membuat niat explicit

4. **Jangan** pakai `unawaited(Future<bool>)` → `void_checks` lint
   - `unawaited` signature-nya `unawaited(Future<void>)`, bukan `Future<T>`
   - Fix: pakai `.ignore()` atau cast ke `Future<void>` atau ubah struktur

**Why:** `discarded_futures` lint menandai Future yang discarded tanpa intent yang jelas. `unawaited()` membuat intent "sengaja tidak di-await" jadi eksplisit, sehingga errors di future tetap bisa di-log di zone handler.

**How to apply:** Setiap kali ada `discarded_futures` info dari analyzer:
- Cek apakah fungsi yang dipanggil return `Future`
- Kalau iya dan memang fire-and-forget, bungkus dengan `unawaited()`
- Kalau nullable (dari `?.`), pakai `(...)?.ignore()`
- Pastikan `dart:async` diimport di library/file yang bersangkutan
