import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

import 'package:musicplayer/themes/app_theme_extension.dart';
import '../../theme/app_colors.dart';
import '../../pages/settings/sleep_timer_page.dart';
import '../../services/audio_playback_state.dart';
import '../../services/sleep_timer_service.dart';
import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import 'player_song_info_sheet.dart';

// ─── PlayerMoreMenu ────────────────────────────────────────────────────────────

class PlayerMoreMenu extends StatefulWidget {
  final LocalSong song;

  const PlayerMoreMenu({super.key, required this.song});

  @override
  State<PlayerMoreMenu> createState() => _PlayerMoreMenuState();
}

class _PlayerMoreMenuState extends State<PlayerMoreMenu> {
  final _key = GlobalKey();
  OverlayEntry? _entry;

  void _open() {
    if (_entry != null) return;

    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final pos   = box.localToGlobal(Offset.zero);
    final size  = box.size;
    const menuW = 220.0;
    final left  = (pos.dx + size.width - menuW).clamp(8.0, double.infinity);
    final top   = pos.dy + size.height + 8;

    _entry = OverlayEntry(builder: (_) => _MoreMenuOverlay(
      left:       left,
      top:        top,
      width:      menuW,
      song:       widget.song,
      onClose:    _close,
      onNavigate: _closeAndNavigate,
    ));

    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _closeAndNavigate(VoidCallback nav) {
    _close();
    nav();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onTap: _open,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color.fromARGB(60, 100, 100, 100),
        ),
        child: const Icon(
          CupertinoIcons.ellipsis_vertical,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ─── Overlay widget ────────────────────────────────────────────────────────────

class _MoreMenuOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double width;
  final LocalSong song;
  final VoidCallback onClose;
  final void Function(VoidCallback nav) onNavigate;

  const _MoreMenuOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.song,
    required this.onClose,
    required this.onNavigate,
  });

  @override
  State<_MoreMenuOverlay> createState() => _MoreMenuOverlayState();
}

class _MoreMenuOverlayState extends State<_MoreMenuOverlay> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AudioService.playbackState.addListener(_refresh);
    SleepTimerService.isActive.addListener(_refresh);
    SleepTimerService.remaining.addListener(_refresh);
  }

  @override
  void dispose() {
    AudioService.playbackState.removeListener(_refresh);
    SleepTimerService.isActive.removeListener(_refresh);
    SleepTimerService.remaining.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c         = AppColors.of(context);
    final state     = AudioService.playbackState.value;
    final active    = SleepTimerService.isActive.value;
    final remaining = SleepTimerService.remaining.value;

    final l = context.l10n;
    String? sleepLabel;
    if (active) {
      if (remaining == null) {
        sleepLabel = l.timerEndOfSong;
      } else {
        final m = remaining.inMinutes;
        final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        sleepLabel = '${m}m ${s}s';
      }
    }

    return Stack(
      children: [
        // Barrier — tap di luar tutup menu
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onClose,
            child: const SizedBox.expand(),
          ),
        ),

        // Menu box
        Positioned(
          left:  widget.left,
          top:   widget.top,
          width: widget.width,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:        c.surface2,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset:     const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuItem(
                    icon:   CupertinoIcons.shuffle,
                    label:  state.shuffleEnabled ? l.shuffleOn : l.shuffleOff,
                    active: state.shuffleEnabled,
                    onTap:  AudioService.toggleShuffle,
                  ),
                  _Divider(c: c),
                  _MenuItem(
                    icon:   _loopIcon(state.loopMode),
                    label:  _loopLabelL10n(l, state.loopMode),
                    active: state.loopMode != LoopMode.off,
                    onTap:  AudioService.cycleLoopMode,
                  ),
                  _Divider(c: c),
                  _MenuItem(
                    icon:  CupertinoIcons.info,
                    label: l.songInfoLabel,
                    onTap: () => widget.onNavigate(
                      () => showModalBottomSheet<void>(
                        context:            context,
                        isScrollControlled: true,
                        useSafeArea:        true,
                        backgroundColor:    Colors.transparent,
                        builder: (_) => PlayerSongInfoSheet(song: widget.song),
                      ),
                    ),
                  ),
                  _Divider(c: c),
                  _SleepTimerItem(
                    active:     active,
                    sleepLabel: sleepLabel,
                    onTap: () => widget.onNavigate(
                      () => showSleepTimerSheet(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static IconData _loopIcon(LoopMode mode) =>
      mode == LoopMode.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat;

  static String _loopLabelL10n(dynamic l, LoopMode mode) =>
      switch (mode) {
        LoopMode.off => l.loopOff,
        LoopMode.all => l.loopAll,
        LoopMode.one => l.loopOne,
      };
}

// ─── Item widgets ──────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c           = AppColors.of(context);
    final accent      = Theme.of(context).colorScheme.primary;
    final labelColor  = active ? accent : c.primaryLabel;
    final iconColor   = active ? accent : c.secondaryLabel;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color:      labelColor,
                fontWeight: FontWeight.w600,
                fontSize:   15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepTimerItem extends StatelessWidget {
  final bool    active;
  final String? sleepLabel;
  final VoidCallback onTap;

  const _SleepTimerItem({
    required this.active,
    required this.sleepLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c      = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.time,
              color: active ? accent : c.secondaryLabel,
              size: 20,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.sleepTimerTitle,
                  style: TextStyle(
                    color:      active ? accent : c.primaryLabel,
                    fontWeight: FontWeight.w600,
                    fontSize:   15,
                  ),
                ),
                if (sleepLabel != null)
                  Text(
                    sleepLabel!,
                    style: TextStyle(
                      color:    c.secondaryLabel,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final AppThemeExtension c;
  const _Divider({required this.c});

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: c.subtleSeparator);
}
