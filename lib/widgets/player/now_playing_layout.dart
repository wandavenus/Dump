/// Geometri tata letak Now Playing (full player).
///
/// Satu sumber kebenaran untuk dua pemakai:
///   • PlayerContent — menata panel kontrol di kolom kanan.
///   • UnifiedMorphPlayer — memposisikan artwork (yang dipegang morph player,
///     bukan PlayerContent) ke slot artwork yang sama.
///
/// Karena keduanya menghitung dari ukuran window yang sama, posisi artwork
/// tidak akan pernah berbeda antara layout dan animasi.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../utils/responsive.dart';

/// Padding horizontal konten full player (sama dengan PlayerContent).
const double kNowPlayingHorizontalPadding = 32.0;

/// Jarak antar kolom pada tata letak dua kolom.
const double kNowPlayingColumnGap = 28.0;

/// Jarak dari atas layar ke awal konten full player:
/// SafeArea.top + Padding(top: 12) + PlayerContent Padding(top: 25).
const double kNowPlayingTopInset = 37.0;

/// Jarak dari bawah layar ke dasar konten full player (di atas safe area).
const double kNowPlayingBottomInset = 20.0;

/// Lebar minimum window agar full player memakai tata letak dua kolom.
const double kNowPlayingTwoColumnMinWidth = 600.0;

/// True bila full player memakai tata letak dua kolom:
/// artwork di kiri, info lagu + kontrol di kanan.
///
/// Berbasis constraint (lebar window), bukan orientasi perangkat; syarat
/// lebar > tinggi mencegah window potret tinggi ikut beralih.
bool useTwoColumnNowPlaying(Size size) =>
    hasRoomForSideBySide(size, minWidth: kNowPlayingTwoColumnMinWidth);

/// Rect (dalam koordinat layar) untuk kolom artwork dan kolom panel kontrol.
@immutable
class NowPlayingColumns {
  const NowPlayingColumns({required this.artwork, required this.panel});

  /// Slot artwork album (persegi).
  final Rect artwork;

  /// Slot untuk judul lagu, progress, dan kontrol pemutaran.
  final Rect panel;
}

/// Menghitung geometri tata letak dua kolom dari ukuran window + safe area.
///
/// Kolom artwork mengambil ~42% lebar konten; artwork selalu persegi dan
/// dibatasi tinggi konten yang tersedia sehingga tidak pernah memenuhi seluruh
/// tinggi layar dan tidak tumpang tindih dengan panel kontrol.
NowPlayingColumns nowPlayingColumns({
  required Size size,
  required double safeTop,
  required double safeBottom,
  double artworkWidthFraction = 0.42,
}) {
  final contentWidth = math.max(
    size.width - kNowPlayingHorizontalPadding * 2,
    0.0,
  );
  final artworkColumnWidth = contentWidth * artworkWidthFraction;
  final panelWidth = math.max(
    contentWidth - artworkColumnWidth - kNowPlayingColumnGap,
    0.0,
  );

  final contentTop = safeTop + kNowPlayingTopInset;
  final contentHeight = math.max(
    size.height - contentTop - (safeBottom + kNowPlayingBottomInset),
    0.0,
  );

  final artworkSize = math.min(artworkColumnWidth, contentHeight);
  final artworkLeft =
      kNowPlayingHorizontalPadding + (artworkColumnWidth - artworkSize) / 2;
  final artworkTop = contentTop + (contentHeight - artworkSize) / 2;

  return NowPlayingColumns(
    artwork: Rect.fromLTWH(artworkLeft, artworkTop, artworkSize, artworkSize),
    panel: Rect.fromLTWH(
      kNowPlayingHorizontalPadding + artworkColumnWidth + kNowPlayingColumnGap,
      contentTop,
      panelWidth,
      contentHeight,
    ),
  );
}

/// Tinggi strip tombol sekunder (toggle lirik/antrean) pada tata letak dua
/// kolom. Strip ini selalu terlihat — termasuk saat overlay lirik/antrean
/// aktif — agar pengguna selalu punya jalan keluar.
const double kNowPlayingSecondaryStrip = 35.0;

// Perkiraan tinggi blok tetap panel (sengaja dilebihkan agar perhitungan jarak
// tidak pernah menghasilkan overflow).
const double _kPanelHeaderHeight = 56.0;
const double _kPanelProgressHeight = 52.0;
const double _kPanelTransportHeight = 74.0;

/// Metrik panel kontrol dua kolom.
@immutable
class NowPlayingPanelMetrics {
  const NowPlayingPanelMetrics({
    required this.transportScale,
    required this.spacing,
    required this.contentHeight,
  });

  /// Skala ukuran ikon transport (1.0 = ukuran penuh seperti di potret).
  final double transportScale;

  /// Jarak vertikal antar kelompok kontrol di dalam panel.
  final double spacing;

  /// Perkiraan tinggi total isi panel (header + progress + transport + jarak).
  final double contentHeight;
}

/// Menghitung skala dan jarak panel dari tinggi panel yang tersedia, sehingga
/// header + progress + transport selalu muat pada window lanskap berapa pun.
NowPlayingPanelMetrics nowPlayingPanelMetrics(double panelHeight) {
  final available = math.max(panelHeight - kNowPlayingSecondaryStrip, 0.0);

  final preferredScale = panelHeight >= 300
      ? 1.0
      : panelHeight >= 230
      ? 0.86
      : 0.72;

  // Keep at least 2 px between control groups, then shrink the transport
  // controls further if a very short window cannot fit the preferred size.
  final maxTransportHeight = math.max(
    available - _kPanelHeaderHeight - _kPanelProgressHeight - 4.0,
    0.0,
  );
  final transportScale = math
      .min(preferredScale, maxTransportHeight / _kPanelTransportHeight)
      .clamp(0.0, 1.0);
  final fixed =
      _kPanelHeaderHeight +
      _kPanelProgressHeight +
      _kPanelTransportHeight * transportScale;
  final spacing = ((available - fixed) / 2).clamp(2.0, 30.0);

  return NowPlayingPanelMetrics(
    transportScale: transportScale,
    spacing: spacing,
    contentHeight: fixed + spacing * 2,
  );
}
