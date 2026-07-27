part of '../../settings_page.dart';

// ── ReplayGain Section ─────────────────────────────────────────────────────

class _ReplayGainSection extends StatefulWidget {
  const _ReplayGainSection();

  @override
  State<_ReplayGainSection> createState() => _ReplayGainSectionState();
}

String _replayGainLabel(BuildContext context, ReplayGainMode mode) {
  final l = context.l10n;
  return switch (mode) {
    ReplayGainMode.off => l.replayGainOff,
    ReplayGainMode.auto => l.replayGainAuto,
    ReplayGainMode.track => l.replayGainTrack,
    ReplayGainMode.album => l.replayGainAlbum,
  };
}

String _replayGainDescription(BuildContext context, ReplayGainMode mode) {
  final l = context.l10n;
  return switch (mode) {
    ReplayGainMode.off => l.replayGainOffDesc,
    ReplayGainMode.auto => l.replayGainAutoDesc,
    ReplayGainMode.track => l.replayGainTrackDesc,
    ReplayGainMode.album => l.replayGainAlbumDesc,
  };
}

class _ReplayGainSectionState extends State<_ReplayGainSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  void _showModePicker(BuildContext context, ReplayGainMode current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplayGainModePicker(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<ReplayGainMode>(
      valueListenable: AudioEffectsService.replayGainMode,
      builder: (context, mode, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — always visible, tappable
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Text(
                      context.l10n.replayGainTitle,
                      style: TextStyle(color: c.primaryLabel, fontSize: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                         _replayGainLabel(context, mode),
                        style: TextStyle(
                            color: c.secondaryLabel, fontSize: 13),
                      ),
                    ),
                    AnimatedRotation(
                      turns:    _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(Icons.keyboard_arrow_down,
                          color: c.primaryLabel.withValues(alpha: 0.38), size: 18),
                    ),
                  ],
                ),
              ),
            ),
            // Collapsible content
            SizeTransition(
              sizeFactor: _ctrl,
              alignment:  Alignment.topCenter,
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode picker row
                    InkWell(
                      onTap: () => _showModePicker(context, mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                   Text(context.l10n.replayGainModeLabel,
                                      style: TextStyle(
                                          color: c.primaryLabel, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(_replayGainLabel(context, mode),
                                      style: TextStyle(
                                          color: c.secondaryLabel,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: c.primaryLabel.withValues(alpha: 0.38), size: 18),
                          ],
                        ),
                      ),
                    ),
                    // Active mode description
                    if (mode != ReplayGainMode.off)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 6),
                        child: Text(
                           _replayGainDescription(context, mode),
                          style: TextStyle(
                              color: c.primaryLabel.withValues(alpha: 0.38),
                              fontSize: 12),
                        ),
                      ),
                    // Preamp slider + clipping protection — only when active
                    if (mode != ReplayGainMode.off) ...[
                      const SizedBox(height: 4),
                      ValueListenableBuilder<double>(
                        valueListenable: AudioEffectsService.replayGainPreamp,
                        builder: (_, preamp, _) => SettingsSliderRow(
                           title: context.l10n.replayGainPreampLabel,
                          subtitle: preamp == 0
                              ? '0 dB'
                              : '${preamp > 0 ? '+' : ''}${preamp.toStringAsFixed(1)} dB',
                          value:     preamp,
                          min:       -15,
                          max:       15,
                          onChanged: AudioEffectsService.setReplayGainPreamp,
                          divisions: 30,
                          showReset: preamp != 0,
                          onReset: () =>
                              AudioEffectsService.setReplayGainPreamp(0),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AudioEffectsService.clippingProtection,
                        builder: (_, clip, _) => SettingsToggleRow(
                           title:     context.l10n.clippingProtection,
                           subtitle:  context.l10n.clippingProtectionSubtitle,
                          value:     clip,
                          onChanged: AudioEffectsService.setClippingProtection,
                        ),
                      ),
                    ],
                    const _BatchScanSection(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ignore: unused_element
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});
  final ReplayGainMode mode;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = mode != ReplayGainMode.off;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFF92D48).withAlpha(30)
            : c.primaryLabel.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFFF92D48).withAlpha(120)
              : c.primaryLabel.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Text(
         _replayGainLabel(context, mode),
        style: TextStyle(
          fontSize:   12,
          color:      active ? const Color(0xFFF92D48) : c.primaryLabel.withValues(alpha: 0.60),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ReplayGainModePicker extends StatelessWidget {
  const _ReplayGainModePicker({required this.current});
  final ReplayGainMode current;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width:  36,
              height: 4,
              decoration: BoxDecoration(
                color:        c.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                   context.l10n.replayGainTitle,
                  style: TextStyle(
                      color: c.primaryLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...ReplayGainMode.values.map(
              (mode) => _ModeOption(mode: mode, selected: mode == current),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected});
  final ReplayGainMode mode;
  final bool           selected;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width:  22,
        height: 22,
        decoration: BoxDecoration(
          shape:  BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFFF92D48) : c.primaryLabel.withValues(alpha: 0.30),
            width: 2,
          ),
          color: selected ? const Color(0xFFF92D48) : Colors.transparent,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
      title: Text(
         _replayGainLabel(context, mode),
        style: TextStyle(
          color:      selected ? const Color(0xFFF92D48) : c.primaryLabel,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize:   15,
        ),
      ),
      subtitle: Text(
         _replayGainDescription(context, mode),
        style: TextStyle(color: c.primaryLabel.withValues(alpha: 0.54), fontSize: 12),
      ),
      onTap: () {
        AudioEffectsService.setReplayGainMode(mode);
        Navigator.pop(context);
      },
    );
  }
}
