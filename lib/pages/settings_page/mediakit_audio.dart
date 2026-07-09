part of '../settings_page.dart';

// ─── MediaKit Audio Section ────────────────────────────────────────────────────
//
// Ditampilkan HANYA saat engine aktif adalah media_kit (bukan Media3).
// Berisi 5 fitur native libmpv:
//   1. Pitch Shifting — diaktifkan via PlayerConfiguration(pitch:true) di engine
//   2. Gapless Playback — mpv gapless-audio
//   3. ReplayGain native — mpv replaygain + replaygain-preamp
//   4. Multi-format — otomatis; ditampilkan sebagai info
//   5. Cache & Buffer — mpv cache + demuxer-readahead-secs

class _MediaKitAudioSection extends StatelessWidget {
  const _MediaKitAudioSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('AUDIO'),
        const SizedBox(height: 6),

        // ── Kecepatan Putar ───────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.playbackSpeed,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Kecepatan Putar',
            subtitle: '${v.toStringAsFixed(2)}x',
            value: v,
            min: 0.25,
            max: 3.0,
            divisions: 22,
            onChanged: AudioEffectsService.setSpeed,
            showReset: v != 1.0,
            onReset: () => AudioEffectsService.setSpeed(1.0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Pitch Shift ───────────────────────────────────────────────────
        ValueListenableBuilder<double>(
          valueListenable: AudioEffectsService.pitchShift,
          builder: (_, v, _) => SettingsSliderRow(
            title: 'Pitch Shift',
            subtitle: v == 0
                ? 'Normal'
                : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitone',
            value: v,
            min: -6,
            max: 6,
            divisions: 24,
            onChanged: AudioEffectsService.setPitch,
            showReset: v != 0,
            onReset: () => AudioEffectsService.setPitch(0),
            expandable: true,
          ),
        ),
        const SettingsDivider(),

        // ── Gapless Playback ──────────────────────────────────────────────
        ValueListenableBuilder<bool>(
          valueListenable: MediaKitSettingsService.gaplessEnabled,
          builder: (_, v, _) => SettingsToggleRow(
            title: 'Gapless Playback',
            subtitle: 'Transisi mulus antar lagu tanpa jeda (mpv gapless-audio)',
            value: v,
            onChanged: MediaKitSettingsService.setGapless,
          ),
        ),
        const SettingsDivider(),

        // ── ReplayGain ────────────────────────────────────────────────────
        const _MkReplayGainSection(),
        const SettingsDivider(),

        // ── Cache & Buffer ────────────────────────────────────────────────
        const _MkCacheSection(),
        const SettingsDivider(),

        // ── Format info ───────────────────────────────────────────────────
        const _MkFormatInfoRow(),
      ],
    );
  }
}

// ─── ReplayGain Sub-section ────────────────────────────────────────────────────

class _MkReplayGainSection extends StatefulWidget {
  const _MkReplayGainSection();

  @override
  State<_MkReplayGainSection> createState() => _MkReplayGainSectionState();
}

class _MkReplayGainSectionState extends State<_MkReplayGainSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MediaKitSettingsService.replayGainEnabled,
      builder: (_, enabled, _) => ValueListenableBuilder<String>(
        valueListenable: MediaKitSettingsService.replayGainMode,
        builder: (_, mode, _) {
          final modeLabel =
              mode == 'track' ? 'Per Lagu (Track)' : 'Per Album';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      const Text('Audio Normalize',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          enabled ? modeLabel : 'Nonaktif',
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 13),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Konten collapsible
              SizeTransition(
                sizeFactor: _ctrl,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _fade,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mode picker row — memilih mode juga mengaktifkan fitur
                      InkWell(
                        onTap: () => _showMkRgModePicker(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('Mode',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text(modeLabel,
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
                      const SettingsDivider(),

                      // Preamp slider — menggeser juga mengaktifkan fitur
                      ValueListenableBuilder<double>(
                        valueListenable:
                            MediaKitSettingsService.replayGainPreampDb,
                        builder: (_, v, _) {
                          final sign = v > 0 ? '+' : '';
                          return SettingsSliderRow(
                            title: 'Preamp',
                            subtitle: v == 0
                                ? '0 dB (default)'
                                : '$sign${v.toStringAsFixed(1)} dB',
                            value: v,
                            min: -15,
                            max: 15,
                            divisions: 30,
                            onChanged: (val) async {
                              await MediaKitSettingsService
                                  .setReplayGainEnabled(true);
                              await MediaKitSettingsService
                                  .setReplayGainPreamp(val);
                            },
                            showReset: v != 0,
                            onReset: () =>
                                MediaKitSettingsService.setReplayGainPreamp(0),
                          );
                        },
                      ),
                      const SettingsDivider(),

                      // Cegah Clipping — toggle juga mengaktifkan fitur
                      ValueListenableBuilder<bool>(
                        valueListenable: MediaKitSettingsService.replayGainClip,
                        builder: (_, v, _) => SettingsToggleRow(
                          title: 'Cegah Clipping',
                          subtitle:
                              'Batasi gain agar tidak distorsi (replaygain-clip)',
                          value: v,
                          onChanged: (val) async {
                            await MediaKitSettingsService
                                .setReplayGainEnabled(true);
                            await MediaKitSettingsService
                                .setReplayGainClip(val);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Cache & Buffer Sub-section ────────────────────────────────────────────────

class _MkCacheSection extends StatefulWidget {
  const _MkCacheSection();

  @override
  State<_MkCacheSection> createState() => _MkCacheSectionState();
}

class _MkCacheSectionState extends State<_MkCacheSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MediaKitSettingsService.cacheEnabled,
      builder: (_, enabled, _) => ValueListenableBuilder<int>(
        valueListenable: MediaKitSettingsService.cacheReadaheadSecs,
        builder: (_, v, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      const Text('Cache & Buffer',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          enabled ? '$v detik' : 'Nonaktif',
                          style: const TextStyle(
                              color: Color(0xFF8E8E93), fontSize: 13),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Konten collapsible — menggeser slider mengaktifkan fitur
              SizeTransition(
                sizeFactor: _ctrl,
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SettingsSliderRow(
                      title: 'Durasi Buffer',
                      subtitle: '$v detik',
                      value: v.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      onChanged: (val) async {
                        await MediaKitSettingsService.setCacheEnabled(true);
                        await MediaKitSettingsService
                            .setCacheReadahead(val.round());
                      },
                      showReset: v != 30,
                      onReset: () async {
                        await MediaKitSettingsService.setCacheEnabled(true);
                        await MediaKitSettingsService.setCacheReadahead(30);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Format Info Row ───────────────────────────────────────────────────────────

class _MkFormatInfoRow extends StatelessWidget {
  const _MkFormatInfoRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.library_music_outlined,
              color: Color(0xFF8E8E93), size: 15),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Format yang Didukung',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                SizedBox(height: 3),
                Text(
                  'FLAC · DSD (DSF/DFF) · APE · OPUS · WavPack · TrueHD · '
                  'OGG Vorbis · AIFF · MP3 · AAC · dan 300+ format lainnya '
                  'via libmpv.',
                  style: TextStyle(color: Color(0xFF636366), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ReplayGain Mode Picker Sheet ─────────────────────────────────────────────

void _showMkRgModePicker(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _MkRgModeSheet(),
  );
}

class _MkRgModeSheet extends StatelessWidget {
  const _MkRgModeSheet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: MediaKitSettingsService.replayGainMode,
      builder: (_, current, _) => SwipeToDismissSheet(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _MkRgModeOption(
                label: 'Per Lagu (Track)',
                value: 'track',
                subtitle: 'Normalisasi berdasarkan gain tiap lagu',
                selected: current == 'track',
              ),
              _MkRgModeOption(
                label: 'Per Album',
                value: 'album',
                subtitle: 'Normalisasi berdasarkan gain seluruh album',
                selected: current == 'album',
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _MkRgModeOption extends StatelessWidget {
  const _MkRgModeOption({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.selected,
  });

  final String label;
  final String value;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        // Memilih mode sekaligus mengaktifkan fitur
        await MediaKitSettingsService.setReplayGainEnabled(true);
        await MediaKitSettingsService.setReplayGainMode(value);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? const Color(0xFFF92D48) : Colors.white,
                      fontSize: 15,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: Color(0xFFF92D48), size: 18),
          ],
        ),
      ),
    );
  }
}
