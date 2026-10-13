/// Konstanta layout global untuk seluruh aplikasi.
///
/// Semua padding kiri konten halaman (judul, label seksi, kartu, banner)
/// harus konsisten di [kPageLeftPadding] = 16 px.
///
/// Pola ListView horizontal:
///   ListView padding left  = [kListLeftPadding]  (10 px)
///   card/item margin left  = [kCardMarginLeft]   ( 6 px)
///   ───────────────────────────────────────────────────
///   total tepi kiri efektif = [kPageLeftPadding] (16 px)
///
/// Skala spasi ([kSpace4]..[kSpace32]) dan skala sudut
/// ([kRadiusXs]..[kRadiusPill]) di bawah ini adalah *satu-satunya* sumber
/// nilai untuk seluruh aplikasi. Nilainya sengaja dipilih sama persis dengan
/// nilai yang sudah dipakai halaman-halaman yang ada, sehingga mengganti
/// literal dengan token TIDAK mengubah tampilan — yang berubah hanya
/// konsistensinya: nilai tidak lagi tersebar sebagai angka lepas di puluhan
/// file, dan penyetelan berikutnya cukup di satu tempat.
///
/// Aturan pemakaian:
/// - jarak antar elemen  → [kSpace4] / [kSpace6] / [kSpace8] / [kSpace12] …
/// - tepi konten halaman → [kPageLeftPadding] (jangan tulis `16` manual)
/// - sudut kartu/artwork → [kRadiusMd] (8) atau [kRadiusLg] (10)
/// - sudut pill/avatar   → [kRadiusPill]
library;

/// Padding kiri standar untuk semua elemen konten halaman.
const double kPageLeftPadding = 16.0;

/// Padding kiri ListView horizontal — dikombinasikan dengan [kCardMarginLeft]
/// sehingga item pertama tepat di [kPageLeftPadding] dari tepi layar.
const double kListLeftPadding = 10.0;

/// Margin kiri item/kartu dalam ListView horizontal.
/// [kListLeftPadding] + [kCardMarginLeft] == [kPageLeftPadding].
const double kCardMarginLeft = 6.0;

// ─── Skala spasi ──────────────────────────────────────────────────────────────

/// Jarak 2 px — pemisah rapat antar baris teks pendukung.
const double kSpace2 = 2.0;

/// Jarak 4 px.
const double kSpace4 = 4.0;

/// Jarak 6 px — jarak kartu/badge.
const double kSpace6 = 6.0;

/// Jarak 8 px — jarak antar elemen dalam satu grup.
const double kSpace8 = 8.0;

/// Jarak 10 px — jarak antar kartu dalam carousel/daftar.
const double kSpace10 = 10.0;

/// Jarak 12 px — jarak antar seksi kecil.
const double kSpace12 = 12.0;

/// Jarak 16 px — jarak standar antar seksi (sama dengan tepi konten).
const double kSpace16 = 16.0;

/// Jarak 20 px.
const double kSpace20 = 20.0;

/// Jarak 24 px.
const double kSpace24 = 24.0;

/// Jarak 32 px.
const double kSpace32 = 32.0;

// ─── Skala sudut ──────────────────────────────────────────────────────────────

/// Sudut 4 px — elemen kecil (chip, thumbnail mini).
const double kRadiusXs = 4.0;

/// Sudut 6 px — artwork mini pada baris lagu.
const double kRadiusSm = 6.0;

/// Sudut 8 px — artwork kartu, permukaan sedang.
const double kRadiusMd = 8.0;

/// Sudut 10 px — kartu daftar, panel.
const double kRadiusLg = 10.0;

/// Sudut 12 px — kartu besar, sheet.
const double kRadiusXl = 12.0;

/// Sudut 16 px — panel besar, dialog.
const double kRadius2xl = 16.0;

/// Sudut pill/kapsul (avatar, chip bulat, tombol navigasi aktif).
const double kRadiusPill = 999.0;
