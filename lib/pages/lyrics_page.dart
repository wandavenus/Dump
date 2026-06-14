import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/lyrics_settings.dart';
import '../models/lyric_line.dart';
import '../services/lyrics_service.dart';
import '../services/media_store_service.dart';
import '../widgets/player/synced_lyrics_view.dart';

/// Halaman lirik penuh layar dengan latar blur album art.
class LyricsPage extends StatefulWidget {
  final LocalSong song;

  const LyricsPage({super.key, required this.song});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage>
    with SingleTickerProviderStateMixin {
  late Future<LyricsResult> _lyricsFuture;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = LyricsService.fetchLyrics(
      title: widget.song.title,
      artist: widget.song.artist,
      filePath: widget.song.path.isNotEmpty ? widget.song.path : null,
    );
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Latar album art blur
          _LyricsBackground(songId: widget.song.id),

          // Overlay gelap + tambahan blur
          ValueListenableBuilder<double>(
            valueListenable: LyricsSettings.bgDim,
            builder: (_, dim, __) => ValueListenableBuilder<double>(
              valueListenable: LyricsSettings.blurStrength,
              builder: (_, blur, __) => Stack(
                fit: StackFit.expand,
                children: [
                  if (blur > 0)
                    BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: blur * 0.3, sigmaY: blur * 0.3),
                      child: const SizedBox.expand(),
                    ),
                  ColoredBox(
                      color: Colors.black.withOpacity(dim.clamp(0.0, 0.95))),
                ],
              ),
            ),
          ),

          // Gradient atas dan bawah
          const _EdgeGradients(),

          // Konten utama
          FadeTransition(
            opacity: _fade,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LyricsHeader(song: widget.song),
                Expanded(
                  child: FutureBuilder<LyricsResult>(
                    future: _lyricsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white24,
                            strokeWidth: 2,
                          ),
                        );
                      }
                      final result = snapshot.data ??
                          const LyricsResult([], LyricsSource.none);
                      if (result.isEmpty) {
                        return _EmptyLyrics(song: widget.song);
                      }
                      return _LyricsBody(result: result);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Latar blur ────────────────────────────────────────────────────────────────

class _LyricsBackground extends StatefulWidget {
  final int songId;
  const _LyricsBackground({required this.songId});

  @override
  State<_LyricsBackground> createState() => _LyricsBackgroundState();
}

class _LyricsBackgroundState extends State<_LyricsBackground> {
  Future<Uint8List?>? _artFuture;

  @override
  void initState() {
    super.initState();
    if (widget.songId > 0) {
      _artFuture = MediaStoreService.getArtwork(widget.songId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_artFuture == null) return const _LyricsGradient();
    return FutureBuilder<Uint8List?>(
      future: _artFuture,
      builder: (_, snap) {
        final art = snap.data;
        if (art == null || art.isEmpty) return const _LyricsGradient();
        return ValueListenableBuilder<double>(
          valueListenable: LyricsSettings.blurStrength,
          builder: (_, blur, __) => SizedBox.expand(
            child: Transform.scale(
              scale: 1.3,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Image.memory(
                  art,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricsGradient extends StatelessWidget {
  const _LyricsGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
        ),
      ),
    );
  }
}

// ─── Gradient tepian ───────────────────────────────────────────────────────────

class _EdgeGradients extends StatelessWidget {
  const _EdgeGradients();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0, left: 0, right: 0, height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.92),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0, height: 100,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.85),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────

class _LyricsHeader extends StatelessWidget {
  final LocalSong song;
  const _LyricsHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, left: 16, right: 16, bottom: 8),
      child: Row(
        children: [
          _CircleButton(
            icon: CupertinoIcons.chevron_down,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 12),
                ),
              ],
            ),
          ),
          _CircleButton(
            icon: CupertinoIcons.textformat,
            onTap: () => _showAppearanceSettings(context),
          ),
        ],
      ),
    );
  }

  void _showAppearanceSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _LyricsAppearanceSheet(),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
          border: Border.all(
              color: Colors.white.withOpacity(0.1), width: 0.5),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ─── Body lirik ────────────────────────────────────────────────────────────────

class _LyricsBody extends StatelessWidget {
  final LyricsResult result;
  const _LyricsBody({required this.result});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SyncedLyricsView(
          lyrics: result.lines,
          padding: const EdgeInsets.fromLTRB(24, 16, 48, 100),
        ),
        // Lencana sumber lirik
        ValueListenableBuilder<bool>(
          valueListenable: LyricsSettings.showSource,
          builder: (_, show, __) {
            if (!show || result.source == LyricsSource.none) {
              return const SizedBox.shrink();
            }
            return Positioned(
              bottom: 14,
              left: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.12), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      result.source == LyricsSource.internet
                          ? CupertinoIcons.globe
                          : CupertinoIcons.doc_text,
                      color: Colors.white.withOpacity(0.45),
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      result.sourceLabel,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45), fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyLyrics extends StatelessWidget {
  final LocalSong song;
  const _EmptyLyrics({required this.song});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note,
                size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              'Lirik tidak ditemukan',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 17,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.title} · ${song.artist}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Tambahkan file .lrc di folder yang sama dengan lagu,\n'
              'atau konfigurasi folder lirik di Pengaturan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet pengaturan tampilan ─────────────────────────────────────────────────

class _LyricsAppearanceSheet extends StatelessWidget {
  const _LyricsAppearanceSheet();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: Colors.black.withOpacity(0.75),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tampilan Lirik',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _sheetLabel('Ukuran Teks'),
                  const SizedBox(height: 8),
                  const _FontSizePicker(),
                  const SizedBox(height: 16),
                  _sheetLabel('Rata Teks'),
                  const SizedBox(height: 8),
                  const _AlignPicker(),
                  const SizedBox(height: 16),
                  _sheetLabel('Warna Aktif'),
                  const SizedBox(height: 8),
                  const _ColorPicker(),
                  const SizedBox(height: 16),
                  _sheetLabel('Kegelapan Latar'),
                  const SizedBox(height: 4),
                  const _DimSlider(),
                  const SizedBox(height: 12),
                  _sheetLabel('Kekuatan Blur'),
                  const SizedBox(height: 4),
                  const _BlurSlider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tampilkan Sumber Lirik',
                            style: TextStyle(
                                color: Colors.white, fontSize: 15)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: LyricsSettings.showSource,
                        builder: (_, v, __) => CupertinoSwitch(
                          value: v,
                          onChanged: LyricsSettings.setShowSource,
                          activeColor: const Color(0xFFF92D48),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _sheetLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      );
}

// ─── Picker widgets ────────────────────────────────────────────────────────────

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker();

  static const _sizes = [
    (label: 'S',  value: 14.0),
    (label: 'M',  value: 18.0),
    (label: 'L',  value: 22.0),
    (label: 'XL', value: 26.0),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.fontSize,
      builder: (_, cur, __) => Row(
        children: _sizes.map((s) {
          final active = cur == s.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setFontSize(s.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AlignPicker extends StatelessWidget {
  const _AlignPicker();

  static const _opts = [
    (label: 'Kiri',   icon: Icons.format_align_left,   value: 'left'),
    (label: 'Tengah', icon: Icons.format_align_center, value: 'center'),
    (label: 'Kanan',  icon: Icons.format_align_right,  value: 'right'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.textAlign,
      builder: (_, cur, __) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setTextAlign(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF92D48)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(o.icon,
                    color: active ? Colors.white : Colors.white54, size: 20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  static const _opts = [
    (label: 'Putih',  color: Color(0xFFFFFFFF), value: 'white'),
    (label: 'Merah',  color: Color(0xFFF92D48), value: 'accent'),
    (label: 'Kuning', color: Color(0xFFFFD60A), value: 'yellow'),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LyricsSettings.activeColor,
      builder: (_, cur, __) => Row(
        children: _opts.map((o) {
          final active = cur == o.value;
          return Expanded(
            child: GestureDetector(
              onTap: () => LyricsSettings.setActiveColor(o.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                height: 40,
                decoration: BoxDecoration(
                  color: active ? o.color : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? null
                      : Border.all(color: o.color.withOpacity(0.4), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  o.label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DimSlider extends StatelessWidget {
  const _DimSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.bgDim,
      builder: (_, v, __) => Row(
        children: [
          const Icon(Icons.brightness_high, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0.2,
              max: 0.95,
              divisions: 15,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBgDim,
            ),
          ),
          const Icon(Icons.brightness_low, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}

class _BlurSlider extends StatelessWidget {
  const _BlurSlider();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LyricsSettings.blurStrength,
      builder: (_, v, __) => Row(
        children: [
          const Icon(CupertinoIcons.photo, color: Colors.white38, size: 16),
          Expanded(
            child: Slider(
              value: v,
              min: 0,
              max: 50,
              divisions: 10,
              activeColor: const Color(0xFFF92D48),
              inactiveColor: Colors.white12,
              onChanged: LyricsSettings.setBlurStrength,
            ),
          ),
          const Icon(Icons.blur_on, color: Colors.white38, size: 16),
        ],
      ),
    );
  }
}
