class SongInfo {
  // ─── General ──────────────────────────────────────────────────────────────
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final String year;
  final String trackNumber;
  final String discNumber;
  final String duration;
  final String? composer;
  final String? comment;
  final String? isrc;
  final String? copyright;
  final String? publisher;

  // ─── Audio ────────────────────────────────────────────────────────────────
  final String format; // file extension in uppercase
  final String bitrate; // formatted, e.g. "256 kbps"
  final String sampleRate; // formatted, e.g. "48 kHz"
  final String? encoder;

  // ─── ReplayGain / Loudness ────────────────────────────────────────────────
  final String? rgTrackGain;
  final String? rgTrackPeak;
  final String? rgAlbumGain;
  final String? rgAlbumPeak;
  final String? r128Track;
  final String? r128Album;
  final String? loudnessSource; // human-readable source label
  final double? appliedGainDb; // gain applied by the player in dB

  // ─── File ─────────────────────────────────────────────────────────────────
  final String fileSize;
  final String filePath;
  final String fileName;
  final String folder;
  final String? modified; // formatted modification date
  final String? dateAdded; // formatted date added (from MediaStore)

  // ─── Embedded Content ─────────────────────────────────────────────────────
  final bool hasEmbeddedLyrics;
  final String? lyricsType; // 'LRC (synced)' | 'Plain text' | null

  // ─── Statistics ───────────────────────────────────────────────────────────
  final int playCount;

  const SongInfo({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.genre = '',
    this.year = '',
    this.trackNumber = '',
    this.discNumber = '',
    required this.duration,
    this.composer,
    this.comment,
    this.isrc,
    this.copyright,
    this.publisher,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    this.encoder,
    this.rgTrackGain,
    this.rgTrackPeak,
    this.rgAlbumGain,
    this.rgAlbumPeak,
    this.r128Track,
    this.r128Album,
    this.loudnessSource,
    this.appliedGainDb,
    required this.fileSize,
    required this.filePath,
    required this.fileName,
    required this.folder,
    this.modified,
    this.dateAdded,
    this.hasEmbeddedLyrics = false,
    this.lyricsType,
    this.playCount = 0,
  });
}
