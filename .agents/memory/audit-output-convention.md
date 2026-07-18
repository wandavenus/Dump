---
name: Audit output convention
description: Aturan output wajib setiap kali melakukan audit (code, security, performance, dsb.)
---

## Aturan

Setiap sesi audit — apapun jenisnya (native code, Kotlin, security, performance, dead code, dll.) — **wajib menghasilkan file `.md` di root repo** yang berisi seluruh temuan secara lengkap.

**Why:** User secara eksplisit meminta ini setelah audit native_code_audit.md (18 Juli 2026). Hasil audit di chat saja tidak cukup — harus ada artefak permanen yang bisa dibaca dan di-track.

## How to apply

- Nama file: deskriptif sesuai scope, misal `native_code_audit.md`, `security_audit.md`, `performance_audit.md`, `kotlin_audit.md`.
- Lokasi: **root repo** (bukan subdirektori).
- Format: Markdown lengkap — summary statistik, semua temuan dengan severity/file/deskripsi/root cause/dampak/confidence/rekomendasi/risiko, matriks prioritas perbaikan, dan temuan positif.
- Timing: Buat file **sebelum** menyatakan audit selesai. Jangan tunggu user meminta.
- Jika audit sangat besar (> 1 sesi), tetap tulis file di akhir setiap sesi dengan status "partial" yang jelas di header.
