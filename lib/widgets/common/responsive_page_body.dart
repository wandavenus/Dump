import 'package:flutter/material.dart';

import '../../utils/responsive.dart';

/// Pembungkus isi halaman yang menyamakan aturan lebar konten di SEMUA halaman.
///
/// Alasan keberadaannya: sebelumnya setiap halaman menyerahkan lebar kontennya
/// langsung ke lebar window. Akibatnya di tablet/desktop baris lagu melebar
/// mengikuti layar sementara grid radio menahan selnya di ukuran desain — dua
/// halaman terlihat memakai aturan berbeda padahal satu aplikasi.
///
/// Perilaku:
/// - **Window sempit (ponsel)**: anak dikembalikan apa adanya, tanpa widget
///   tambahan sama sekali. Tata letak ponsel potret — acuan desain — dijamin
///   tidak berubah, bukan sekadar "mendekati sama".
/// - **Window lebar**: konten dibatasi [kMaxContentWidth] dan dipusatkan,
///   sehingga setiap halaman memakai kolom baca yang sama.
class ResponsivePageBody extends StatelessWidget {
  const ResponsivePageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    // Ponsel: kembalikan anak tanpa membungkus apa pun, supaya pohon widget
    // dan ukuran hasilnya identik dengan sebelum perubahan ini.
    if (width <= kMaxContentWidth) return child;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: child,
      ),
    );
  }
}
