# High-Value Analyzer Fixes — 27 Juli 2026

## Scope

Audit ini hanya memperbaiki diagnostic analyzer yang berhubungan dengan:

- compile-time errors dan type safety;
- penggunaan `dynamic` pada parsing provider lirik;
- future yang sengaja berjalan tanpa `await`;
- penggunaan `BuildContext` setelah async gap;
- inference warning yang memengaruhi kontrak modal/dialog.

Lint kosmetik seperti quote style, type annotation style, dan panjang baris tidak
diubah.

## Hasil

- **Error compile-time sebelum:** 1
- **Error compile-time sesudah:** 0
- **Warning analyzer sebelum:** 6
- **Warning analyzer sesudah:** 0
- **Info/lint tersisa:** 13.874, mayoritas style lint yang sengaja tidak
  disentuh sesuai scope.

## Perubahan utama

- Memperbaiki typo completion pada `CancellationToken.guardFuture`.
- Menambahkan tipe eksplisit pada `Future.delayed`, modal, dan dialog.
- Menandai future animasi, clipboard, navigasi, dan operasi background yang
  memang sengaja tidak ditunggu dengan `unawaited`.
- Menghindari akses `BuildContext` setelah async gap pada sheet playlist.
- Menambahkan normalisasi map JSON bertipe untuk provider Kuwo, Kugou, NetEase,
  QQ Music, dan Apple Music.

## Validasi

Perintah yang dijalankan:

```bash
flutter analyze lib test
```

Hasil: tidak ada error atau warning analyzer; diagnostic yang tersisa adalah
info/lint di luar scope, tanpa perubahan arsitektur atau behavior aplikasi.