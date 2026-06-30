enum ReplayGainMode {
  off,
  auto,
  track,
  album;

  String get label => switch (this) {
    ReplayGainMode.off => 'Off',
    ReplayGainMode.auto => 'Auto',
    ReplayGainMode.track => 'Track Gain',
    ReplayGainMode.album => 'Album Gain',
  };

  String get description => switch (this) {
    ReplayGainMode.off => 'Tidak ada normalisasi volume',
    ReplayGainMode.auto => 'Gunakan sumber loudness terbaik yang tersedia',
    ReplayGainMode.track => 'Normalisasi setiap lagu secara independen',
    ReplayGainMode.album =>
      'Pertahankan hubungan volume antar lagu dalam album',
  };
}
