# Native DSP C/C++ Audit --- Production Readiness

## Objective

Lakukan audit **MENYELURUH** terhadap seluruh kode Native C/C++ pada
project ini.

Target:

-   `android/app/src/main/cpp/**`
-   seluruh library native
-   seluruh DSP
-   seluruh JNI
-   seluruh audio processing
-   seluruh SIMD / NEON
-   seluruh util native

**JANGAN** hanya menjalankan analyzer (clang-tidy, cppcheck, dll).

Lakukan audit manual seperti senior C++ engineer yang mengaudit audio
engine production.

------------------------------------------------------------------------

# Audit Scope

## 1. Undefined Behavior (UB)

Cari:

-   signed integer overflow
-   unsigned overflow yang menyebabkan bug
-   shift UB
-   strict aliasing violation
-   invalid cast
-   alignment issue
-   dangling pointer
-   use-after-free
-   use-after-move
-   null dereference
-   iterator invalidation
-   invalid lifetime object

------------------------------------------------------------------------

## 2. Memory Safety

Cari:

-   memory leak
-   double free
-   invalid free
-   heap corruption
-   stack corruption
-   out-of-bound read
-   out-of-bound write
-   buffer overflow
-   buffer underflow
-   uninitialized memory
-   invalid pointer arithmetic

------------------------------------------------------------------------

## 3. Thread Safety

Cari:

-   race condition
-   deadlock
-   mutex misuse
-   atomic misuse
-   thread lifetime issue
-   concurrent container access
-   audio thread violation
-   realtime thread blocking

------------------------------------------------------------------------

## 4. Audio DSP

Cari:

-   clipping
-   denormal float
-   NaN propagation
-   Infinity propagation
-   overflow
-   underflow
-   precision loss
-   channel mismatch
-   mono/stereo bug
-   sample-rate bug
-   frame alignment bug
-   latency issue
-   phase inversion
-   DSP ordering issue
-   SIMD vs scalar mismatch

------------------------------------------------------------------------

## 5. JNI

Cari:

-   LocalRef leak
-   GlobalRef leak
-   exception tidak dicek
-   GetPrimitiveArrayCritical misuse
-   UTF string leak
-   jobject ownership
-   fd ownership
-   native resource leak

------------------------------------------------------------------------

## 6. Resource Management

Cari:

-   fd leak
-   FILE leak
-   mmap leak
-   handle leak
-   duplicate ownership
-   RAII violation
-   ownership ambiguity

------------------------------------------------------------------------

## 7. Performance

Cari:

-   malloc/new pada audio thread
-   unnecessary allocation
-   memcpy berlebihan
-   vector resize berulang
-   unnecessary copy
-   lock pada realtime thread
-   cache miss
-   branch yang bisa dihilangkan
-   expensive operation di callback audio

------------------------------------------------------------------------

## 8. SIMD / NEON

Audit:

-   alignment
-   fallback scalar
-   tail processing
-   load/store safety
-   precision consistency
-   register misuse
-   undefined intrinsic usage

------------------------------------------------------------------------

## 9. Numerical Stability

Cari:

-   division by zero
-   log(0)
-   sqrt negatif
-   exp overflow
-   float accumulation error
-   RMS calculation
-   LUFS calculation
-   catastrophic cancellation
-   floating-point precision issue

------------------------------------------------------------------------

## 10. Security

Cari:

-   integer overflow
-   unsafe memcpy
-   unsafe memmove
-   unsafe sprintf
-   unchecked input
-   invalid size calculation
-   path traversal
-   malformed metadata handling

------------------------------------------------------------------------

## 11. Architecture

Cari:

-   dead code
-   unreachable code
-   duplicate implementation
-   abstraction rusak
-   API tidak konsisten
-   ownership ambigu
-   coupling berlebihan
-   code yang bisa disederhanakan tanpa mengubah perilaku

------------------------------------------------------------------------

# Audit Rules

Jangan membuat laporan berdasarkan asumsi.

Jika suatu bug **tidak dapat dibuktikan**, tandai sebagai:

> **Tidak Terbukti**

Jangan mengubah severity hanya karena "berpotensi".

Prioritaskan bug yang benar-benar dapat terjadi pada production.

Jangan melaporkan style issue, formatting, atau naming kecuali berdampak
pada correctness, reliability, memory safety, atau performance.

------------------------------------------------------------------------

# Output Format

Untuk setiap temuan tampilkan:

## Severity

-   Critical
-   High
-   Medium
-   Low

## Lokasi

-   File
-   Function
-   Line

## Penjelasan

-   Penyebab bug
-   Bagaimana bug terjadi
-   Kapan bug muncul
-   Dampaknya
-   Mengapa severity tersebut dipilih

## Solusi

Berikan patch yang paling aman.

Jika terdapat beberapa solusi, jelaskan trade-off masing-masing.

------------------------------------------------------------------------

# Final Report

Di akhir audit berikan ringkasan berikut:

## Ringkasan

-   Jumlah Critical
-   Jumlah High
-   Jumlah Medium
-   Jumlah Low

## Production Readiness

Berikan penilaian:

-   Belum Layak
-   Perlu Perbaikan Minor
-   Hampir Production Ready
-   Production Ready

## Daftar Prioritas

Urutkan seluruh temuan berdasarkan prioritas perbaikan dari yang paling
penting hingga yang paling rendah.
