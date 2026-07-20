# Replit Agent Task --- Fix Seluruh Temuan Audit Native

## Objective

Perbaiki **seluruh** temuan pada `Native_Audit_Merged_2026-07-20.md`.

## Persyaratan Wajib

-   Jangan mengubah arsitektur kecuali benar-benar diperlukan.
-   Jangan melakukan refactor yang tidak berkaitan.
-   Jangan mengubah public API kecuali memang dibutuhkan oleh fix.
-   Jangan menurunkan performa audio thread.
-   Jangan mengubah karakter DSP, output audio, ReplayGain, limiter,
    compressor, crossfeed, maupun loudness.
-   Semua perubahan harus backward compatible.
-   Semua fix harus mempertahankan behavior normal.
-   Jika sebuah fix memiliki trade-off, cari pendekatan lain hingga
    trade-off tersebut hilang atau menjadi tidak relevan secara praktis.
-   Jangan menyelesaikan masalah dengan disable feature.

## Target

Perbaiki seluruh temuan:

1.  metadata_region.cpp --- HIGH
2.  tag_writer.cpp --- MEDIUM
3.  replaygain_jni.cpp --- LocalRef leak
4.  tag_writer.cpp --- FsyncGuard logging
5.  replaygain_jni.cpp --- bounds validation
6.  stretch_jni.cpp --- steady_clock pada audio callback
7.  stretch_jni.cpp --- warmup allocation
8.  jni_common.h --- dead enum
9.  tag_writer.h --- dead field
10. gain_processor.c
11. dsp_pipeline.c
12. loudness_processor.c
13. replaygain_processor.c
14. loudness_processor.c (documentation / reset limitation)

## Validasi Setiap Fix

Untuk setiap temuan, lakukan:

-   jelaskan root cause
-   jelaskan mengapa solusi aman
-   jelaskan mengapa tidak mengubah output audio
-   jelaskan mengapa tidak menambah latency
-   jelaskan mengapa tidak menambah alokasi pada audio thread
-   jelaskan mengapa tidak memperburuk thread safety
-   jelaskan mengapa tidak ada regression

## Verifikasi Wajib

Sebelum selesai, pastikan:

-   build berhasil
-   analyzer bersih untuk file yang diubah
-   tidak ada warning baru
-   tidak ada memory leak baru
-   tidak ada race condition baru
-   tidak ada UB baru
-   tidak ada deadlock baru
-   tidak ada API break
-   tidak ada performance regression
-   tidak ada perubahan kualitas audio
-   tidak ada perubahan loudness, limiter, compressor, crossfeed,
    ReplayGain, maupun DSP output selain yang memang diperbaiki

## Jika menemukan trade-off

Jangan langsung implementasikan.

Cari alternatif yang:

-   lebih aman
-   tanpa regression
-   tanpa perubahan behaviour
-   tanpa overhead berarti

Jika memang secara teknis tidak mungkin menghilangkan trade-off
sepenuhnya, jelaskan:

-   trade-off yang tersisa
-   alasan teknis
-   mengapa itu merupakan pilihan terbaik dibanding alternatif lain

Jangan menyatakan selesai sebelum seluruh poin di atas telah
diverifikasi.
