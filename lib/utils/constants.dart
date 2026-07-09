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
library;

/// Padding kiri standar untuk semua elemen konten halaman.
const double kPageLeftPadding = 16.0;

/// Padding kiri ListView horizontal — dikombinasikan dengan [kCardMarginLeft]
/// sehingga item pertama tepat di [kPageLeftPadding] dari tepi layar.
const double kListLeftPadding = 10.0;

/// Margin kiri item/kartu dalam ListView horizontal.
/// [kListLeftPadding] + [kCardMarginLeft] == [kPageLeftPadding].
const double kCardMarginLeft = 6.0;
