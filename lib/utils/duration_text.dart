import '../l10n/app_localizations.dart';
import '../models/local_song.dart';

/// Memformat total durasi daftar lagu (agregat jam/menit, l10n-aware).
///
/// Dipakai oleh footer halaman Album dan Artist — satu sumber kebenaran agar
/// format tidak pernah melenceng di salah satu halaman.
String formatTotalDuration(List<LocalSong> songs, AppLocalizations l) {
  final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
  final h = total.inHours;
  final m = total.inMinutes.remainder(60);
  if (h > 0) return l.durationHoursMinutes(h, m);
  return l.durationOnlyMinutes(m);
}
