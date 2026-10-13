/// Helper responsif bersama untuk seluruh aplikasi.
///
/// Semua keputusan di sini berbasis *constraint yang tersedia* (ukuran window
/// saat ini), bukan orientasi perangkat: split-screen dan window dengan
/// constraint terbatas harus mendapat perlakuan yang sama dengan ponsel
/// lanskap.
library;

import 'package:flutter/widgets.dart';

/// Tinggi window (logical px) yang menjadi acuan [shortWindowScale].
///
/// Dipilih di bawah tinggi ponsel potret terkecil yang umum (~640) sehingga
/// layout potret selalu memakai skala penuh, sementara window pendek
/// (lanskap ponsel, panel split-screen) mendapat skala yang lebih kecil.
const double kReferenceWindowHeight = 600.0;

/// Ambang lebar window untuk tata letak "lebar" (tablet, desktop, jendela
/// besar). Satu-satunya sumber angka ini — jangan menulis 600 lepas di widget.
///
/// Di bawah ambang ini aplikasi memakai tata letak acuan ponsel potret, jadi
/// perilaku dan ukuran ponsel tidak pernah berubah.
const double kWideLayoutMinWidth = 600.0;

/// Lebar maksimum kolom konten saat window lebar.
///
/// Tanpa batas ini, baris lagu di tablet melebar mengikuti layar (mis. 1000+ px
/// untuk satu judul lagu) sementara grid radio menahan selnya di ~112 px — dua
/// halaman jadi terasa berbeda aturannya. Dengan batas ini semua halaman
/// memakai kolom baca yang sama dan tetap di tengah.
///
/// Nilai 720 dipilih > lebar ponsel potret terlebar (~430) dan > ambang
/// [kWideLayoutMinWidth], sehingga window ponsel tidak pernah terkena clamp.
const double kMaxContentWidth = 720.0;

/// Lebar maksimum konten halaman untuk window saat ini.
///
/// Mengembalikan lebar window apa adanya bila window sempit (ponsel), dan
/// [kMaxContentWidth] bila window lebar. Karena window ponsel selalu lebih
/// sempit dari [kMaxContentWidth], fungsi ini tidak pernah mengubah tata letak
/// ponsel — ia hanya menahan konten agar tidak melebar di tablet/desktop.
double contentMaxWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width < kMaxContentWidth ? width : kMaxContentWidth;
}

/// Batas bawah [shortWindowScale] — mencegah blok tetap menjadi terlalu kecil
/// untuk disentuh.
const double kMinShortWindowScale = 0.62;

/// Faktor skala di rentang `[kMinShortWindowScale, 1.0]` untuk blok berukuran
/// tetap yang semula disetel untuk viewport potret (carousel, banner, artwork).
///
/// Dipakai agar satu baris carousel tidak menghabiskan seluruh tinggi layar
/// lanskap. Murni berbasis tinggi: window potret (tinggi >= acuan) tidak pernah
/// berubah.
double shortWindowScale(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  return (height / kReferenceWindowHeight).clamp(kMinShortWindowScale, 1.0);
}

/// Jumlah kolom untuk grid adaptif.
///
/// Kolom dihitung dari lebar window dibagi [targetTileWidth] sehingga lebar
/// tiap sel tetap mendekati desain awal, lalu dijepit ke
/// [minColumns]..[maxColumns].
int responsiveColumns(
  BuildContext context, {
  required double targetTileWidth,
  int minColumns = 2,
  int maxColumns = 6,
}) {
  final width = MediaQuery.sizeOf(context).width;
  return (width / targetTileWidth).floor().clamp(minColumns, maxColumns);
}

/// True bila window saat ini cukup lebar dan cukup "melebar" (lebar > tinggi)
/// untuk memakai tata letak dua kolom berdampingan.
///
/// [minWidth] menjaga agar panel samping tetap punya ruang layak; perbandingan
/// lebar > tinggi mencegah window potret tinggi ikut beralih ke mode samping.
bool hasRoomForSideBySide(
  Size size, {
  double minWidth = kWideLayoutMinWidth,
}) => size.width >= minWidth && size.width > size.height;
