part of '../../settings_page.dart';

// ── ReplayGain Section ─────────────────────────────────────────────────────

class _ReplayGainSection extends StatefulWidget {
  const _ReplayGainSection();

  @override
  State<_ReplayGainSection> createState() => _ReplayGainSectionState();
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
                    const Text(
                      'Audio Normalize',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        mode.label,
                        style: const TextStyle(
                            color: Color(0xFF8E8E93), fontSize: 13),
                      ),
                    ),
                    AnimatedRotation(
                      turns:    _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white38, size: 18),
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
                                  const Text('Mode',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 15)),
                                  const SizedBox(height: 2),
                                  Text(mode.label,
                                      style: const TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white38, size: 18),
                          ],
                        ),
                      ),
                    ),
                    // Active mode description
                    if (mode != ReplayGainMode.off)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 6),
                        child: Text(
                          mode.description,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    // Preamp slider + clipping protection — only when active
                    if (mode != ReplayGainMode.off) ...[
                      const SizedBox(height: 4),
                      ValueListenableBuilder<double>(
                        valueListenable: AudioEffectsService.replayGainPreamp,
                        builder: (_, preamp, _) => SettingsSliderRow(
                          title: 'Preamp',
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
                          title:     'Clipping Protection',
                          subtitle:  'Cegah distorsi saat gain melebihi 0 dBFS',
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
    final active = mode != ReplayGainMode.off;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFF92D48).withAlpha(30)
            : Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? const Color(0xFFF92D48).withAlpha(120)
              : Colors.white.withAlpha(30),
          width: 0.8,
        ),
      ),
      child: Text(
        mode.label,
        style: TextStyle(
          fontSize:   12,
          color:      active ? const Color(0xFFF92D48) : Colors.white60,
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
    return SwipeToDismissSheet(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        const Color(0xFF1C1C1E),
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
                color:        Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mode Audio Normalize',
                  style: TextStyle(
                      color: Colors.white,
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width:  22,
        height: 22,
        decoration: BoxDecoration(
          shape:  BoxShape.circle,
          border: Border.all(
            color: selected ? const Color(0xFFF92D48) : Colors.white30,
            width: 2,
          ),
          color: selected ? const Color(0xFFF92D48) : Colors.transparent,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
      title: Text(
        mode.label,
        style: TextStyle(
          color:      selected ? const Color(0xFFF92D48) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize:   15,
        ),
      ),
      subtitle: Text(
        mode.description,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: () {
        AudioEffectsService.setReplayGainMode(mode);
        Navigator.pop(context);
      },
    );
  }
}
