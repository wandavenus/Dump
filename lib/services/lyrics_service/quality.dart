/// Kualitas lirik dari tertinggi ke terendah (ordinal = prioritas).
enum LyricsQuality {
  wordTimedLrc,    // Enhanced LRC dengan word-timing <mm:ss.xx> per kata
  charTimedLrc,    // Enhanced LRC dengan character-timing
  lineTimedLrc,    // Standard LRC [mm:ss.xx] per baris
  plainLrc,        // LRC dengan struktur tapi tanpa timestamp bermakna
  unsyncedLyrics,  // Teks biasa tanpa timing
  none,            // Tidak ada lirik
}

extension LyricsQualityX on LyricsQuality {
  /// True jika kualitas ini LEBIH BAIK dari [other].
  bool isBetterThan(LyricsQuality other) => index < other.index;

  bool get hasTiming => index <= LyricsQuality.lineTimedLrc.index;
  bool get isEnhanced => index <= LyricsQuality.charTimedLrc.index;
  bool get isWordTimed => this == LyricsQuality.wordTimedLrc;

  String get displayName {
    switch (this) {
      case LyricsQuality.wordTimedLrc:   return 'Word-timed LRC';
      case LyricsQuality.charTimedLrc:   return 'Char-timed LRC';
      case LyricsQuality.lineTimedLrc:   return 'Synced LRC';
      case LyricsQuality.plainLrc:       return 'Plain LRC';
      case LyricsQuality.unsyncedLyrics: return 'Unsynced';
      case LyricsQuality.none:           return 'None';
    }
  }

  /// Serialisasi untuk cache disk.
  String toJson() => name;
}

/// Deserialisasi dari string nama enum (untuk cache disk).
LyricsQuality lyricsQualityFromJson(String? s) {
  return LyricsQuality.values.firstWhere(
    (q) => q.name == s,
    orElse: () => LyricsQuality.none,
  );
}
