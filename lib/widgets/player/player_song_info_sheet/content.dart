part of '../player_song_info_sheet.dart';

class _SongInfoContent extends StatelessWidget {
  final SongInfo songInfo;

  /// Live audio format from ExoPlayer's decoder (via audioFormat EventChannel).
  /// When non-null, its values supersede the file-metadata equivalents in the
  /// AUDIO QUALITY section — they reflect what is actually being decoded now.
  final Map<String, dynamic>? liveFormat;

  const _SongInfoContent({
    required this.songInfo,
    this.liveFormat,
  });

  @override
  Widget build(BuildContext context) {
    final live = liveFormat;

    // "valid" live data: at least sampleRate must be a positive int.
    // An all-zero map means the player is idle / no audio track selected.
    final hasLive =
        live != null && ((live['sampleRate'] as num?)?.toInt() ?? 0) > 0;

    // Compute Bit Depth string once; empty string means "skip this row".
    final bitDepth = hasLive
        ? _fmtPcmEncoding((live['pcmEncoding'] as num?)?.toInt() ?? 0)
        : '';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Title & artist ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  songInfo.title,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).primaryLabel,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  songInfo.artist,
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.of(context).secondaryLabel,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Track details ────────────────────────────────────────────────
          _InfoSection(
            title: 'DETAILS',
            children: [
              PlayerSongInfoRow(label: 'Album', value: songInfo.album),
              if (songInfo.albumArtist.isNotEmpty)
                PlayerSongInfoRow(
                    label: 'Album Artist', value: songInfo.albumArtist),
              if (songInfo.genre.isNotEmpty)
                PlayerSongInfoRow(label: 'Genre', value: songInfo.genre),
              PlayerSongInfoRow(label: 'Year', value: songInfo.year),
              if (songInfo.trackNumber.isNotEmpty)
                PlayerSongInfoRow(
                  label: 'Track',
                  value: songInfo.discNumber.isNotEmpty
                      ? '${songInfo.trackNumber} (Disc ${songInfo.discNumber})'
                      : songInfo.trackNumber,
                ),
              PlayerSongInfoRow(label: 'Duration', value: songInfo.duration),
            ],
          ),
          const SizedBox(height: 16),

          // ── Audio quality ─────────────────────────────────────────────────
          // Live data (ExoPlayer decoder) is preferred over file metadata where
          // available.  Extra fields (Channels, Bit Depth) are shown only when
          // live data is present.  File Size always comes from metadata.
          _InfoSection(
            title: 'AUDIO QUALITY',
            children: [
              // Format — MIME type label > file extension
              PlayerSongInfoRow(
                label: 'Format',
                value: hasLive
                    ? _fmtMimeType(
                        live['mimeType'] as String? ?? '',
                        songInfo.format,
                      )
                    : songInfo.format,
              ),

              // Bit Depth — only present for PCM formats (WAV, some FLAC)
              if (hasLive && bitDepth.isNotEmpty)
                PlayerSongInfoRow(label: 'Bit Depth', value: bitDepth),

              // Sample Rate — live Hz > metadata string
              PlayerSongInfoRow(
                label: 'Sample Rate',
                value: hasLive
                    ? _fmtSampleRate(
                        (live['sampleRate'] as num?)?.toInt() ?? 0,
                        songInfo.sampleRate,
                      )
                    : songInfo.sampleRate,
              ),

              // Channels — live only
              if (hasLive)
                PlayerSongInfoRow(
                  label: 'Channels',
                  value: _fmtChannels(
                    (live['channelCount'] as num?)?.toInt() ?? 0,
                  ),
                ),

              // Bitrate — live bps > metadata string; 0 bps = lossless
              PlayerSongInfoRow(
                label: 'Bitrate',
                value: hasLive
                    ? _fmtBitrate(
                        (live['bitrate'] as num?)?.toInt() ?? 0,
                        songInfo.bitrate,
                      )
                    : songInfo.bitrate,
              ),

              // Encoder — from embedded tags only, skip when absent
              if ((songInfo.encoder ?? '').isNotEmpty)
                PlayerSongInfoRow(label: 'Encoder', value: songInfo.encoder!),

              // File Size — always from metadata (no native live equivalent)
              PlayerSongInfoRow(label: 'File Size', value: songInfo.fileSize),
            ],
          ),
          const SizedBox(height: 16),

          // ── Loudness / ReplayGain ──────────────────────────────────────────
          // Only shown when the player actually has a resolved gain to apply
          // — otherwise this section would just be a wall of "—".
          if (songInfo.appliedGainDb != null) ...[
            _InfoSection(
              title: 'LOUDNESS',
              children: [
                PlayerSongInfoRow(
                  label: 'Applied Gain',
                  value:
                      '${songInfo.appliedGainDb!.toStringAsFixed(1)} dB',
                ),
                if ((songInfo.loudnessSource ?? '').isNotEmpty)
                  PlayerSongInfoRow(
                    label: 'Source',
                    value: songInfo.loudnessSource!,
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Embedded content ─────────────────────────────────────────────
          if (songInfo.hasEmbeddedLyrics) ...[
            _InfoSection(
              title: 'EMBEDDED CONTENT',
              children: [
                PlayerSongInfoRow(
                  label: 'Lyrics',
                  value: songInfo.lyricsType ?? 'Yes',
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Statistics ────────────────────────────────────────────────────
          if (songInfo.playCount > 0) ...[
            _InfoSection(
              title: 'STATISTICS',
              children: [
                PlayerSongInfoRow(
                  label: 'Play Count',
                  value: '${songInfo.playCount}',
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── File ──────────────────────────────────────────────────────────
          _InfoSection(
            title: 'FILE',
            children: [
              PlayerSongInfoRow(label: 'File Name', value: songInfo.fileName),
              if (songInfo.folder.isNotEmpty)
                PlayerSongInfoRow(label: 'Folder', value: songInfo.folder),
              if ((songInfo.dateAdded ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'Date Added', value: songInfo.dateAdded!),
              if ((songInfo.modified ?? '').isNotEmpty)
                PlayerSongInfoRow(label: 'Modified', value: songInfo.modified!),
            ],
          ),

          // ── Additional info — credits, raw tags; collapsed by default ────
          _CollapsibleSection(
            title: 'ADDITIONAL INFO',
            children: [
              if ((songInfo.composer ?? '').isNotEmpty)
                PlayerSongInfoRow(label: 'Composer', value: songInfo.composer!),
              if ((songInfo.publisher ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'Publisher', value: songInfo.publisher!),
              if ((songInfo.copyright ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'Copyright', value: songInfo.copyright!),
              if ((songInfo.isrc ?? '').isNotEmpty)
                PlayerSongInfoRow(label: 'ISRC', value: songInfo.isrc!),
              if ((songInfo.comment ?? '').isNotEmpty)
                PlayerSongInfoRow(label: 'Comment', value: songInfo.comment!),
              if ((songInfo.rgTrackGain ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'RG Track Gain', value: songInfo.rgTrackGain!),
              if ((songInfo.rgTrackPeak ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'RG Track Peak', value: songInfo.rgTrackPeak!),
              if ((songInfo.rgAlbumGain ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'RG Album Gain', value: songInfo.rgAlbumGain!),
              if ((songInfo.rgAlbumPeak ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'RG Album Peak', value: songInfo.rgAlbumPeak!),
              if ((songInfo.r128Track ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'R128 Track Gain', value: songInfo.r128Track!),
              if ((songInfo.r128Album ?? '').isNotEmpty)
                PlayerSongInfoRow(
                    label: 'R128 Album Gain', value: songInfo.r128Album!),
            ],
          ),
          const SizedBox(height: 8),
          _FilePathSection(filePath: songInfo.filePath),
        ],
      ),
    );
  }

  // ── Live-format display helpers ───────────────────────────────────────────

  /// Maps a Media3 MIME type to a human-readable codec name.
  /// Falls back to [fallback] (e.g. file extension from metadata) when the
  /// MIME string is empty or unrecognised.
  static String _fmtMimeType(String mime, String fallback) {
    final label = switch (mime) {
      'audio/flac'                       => 'FLAC',
      'audio/mpeg' || 'audio/mp3'        => 'MP3',
      'audio/aac'  || 'audio/mp4a-latm'  => 'AAC',
      'audio/ogg'  || 'audio/vorbis'     => 'OGG Vorbis',
      'audio/opus'                       => 'Opus',
      'audio/wav'  || 'audio/x-wav'      => 'WAV',
      'audio/alac' || 'audio/x-alac'     => 'ALAC',
      'audio/raw'  || 'audio/pcm'        => 'PCM',
      _ => mime.isNotEmpty ? mime.split('/').last.toUpperCase() : '',
    };
    return label.isNotEmpty ? label : fallback;
  }

  /// Formats a sample-rate in Hz to "44.1 kHz" / "96 kHz".
  /// Falls back to [fallback] when [hz] is zero or negative.
  static String _fmtSampleRate(int hz, String fallback) {
    if (hz <= 0) return fallback;
    final khz = hz / 1000.0;
    return (khz == khz.truncateToDouble())
        ? '${khz.toInt()} kHz'
        : '${khz.toStringAsFixed(1)} kHz';
  }

  /// Maps a channel count to a descriptive label.
  static String _fmtChannels(int count) => switch (count) {
    1 => 'Mono',
    2 => 'Stereo',
    4 => 'Quad',
    6 => '5.1 Surround',
    8 => '7.1 Surround',
    _ => count > 0 ? '$count ch' : '—',
  };

  /// Formats bitrate from bits/second to "320 kbps".
  /// Returns the metadata [fallback] when [bps] is 0 (lossless), or
  /// "Lossless" when the fallback itself is empty / unknown.
  static String _fmtBitrate(int bps, String fallback) {
    if (bps > 0) return '${(bps / 1000).round()} kbps';
    if (fallback.isNotEmpty && fallback != 'Unknown') return fallback;
    return 'Lossless';
  }

  /// Maps Android [AudioFormat.ENCODING_*] int to a bit-depth label.
  /// Returns an empty string for compressed formats (encoding 0 / unknown)
  /// so the caller can skip rendering the row entirely.
  static String _fmtPcmEncoding(int encoding) => switch (encoding) {
    2 => '16-bit PCM',
    3 => '8-bit PCM',
    4 => '32-bit Float',
    5 => '32-bit PCM',
    6 => '24-bit PCM',
    _ => '',
  };
}
