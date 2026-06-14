part of '../settings_page.dart';

// ─── DEBUG ────────────────────────────────────────────────────────────────────

class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                'DEBUG',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF92D48),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF92D48).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('MODE AKTIF',
                  style: TextStyle(
                      color: Color(0xFFF92D48),
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Notification icon picker
        ValueListenableBuilder<int>(
          valueListenable: _DebugState.notifIcon,
          builder: (_, idx, __) => _NotifIconRow(selectedIdx: idx),
        ),
        const SettingsDivider(),

        // Audio session info
        _AudioSessionInfo(),
        const SettingsDivider(),

        // Effect status
        _EffectStatusRow(),
        const SettingsDivider(),

        // Exit debug
        SettingsActionRow(
          title: 'Keluar Mode Debug',
          trailing: '',
          onTap: () => _DebugState.enabled.value = false,
          isDestructive: true,
        ),
        const SettingsDivider(),
      ],
    );
  }
}

class _NotifIconRow extends StatelessWidget {
  final int selectedIdx;
  const _NotifIconRow({required this.selectedIdx});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showIconPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.notifications_none,
                color: Color(0xFF8E8E93), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ikon Notifikasi Pemutar',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    _DebugState.notifIcons[selectedIdx].label,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }

  void _showIconPicker(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Pilih Ikon Notifikasi'),
        message: const Text('Berlaku setelah restart app'),
        actions: List.generate(
          _DebugState.notifIcons.length,
          (i) => CupertinoActionSheetAction(
            isDefaultAction: i == selectedIdx,
            onPressed: () {
              _DebugState.notifIcon.value = i;
              Navigator.of(context).pop();
            },
            child: Text(_DebugState.notifIcons[i].label),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ),
    );
  }
}

class _AudioSessionInfo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Info Audio Engine',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          _InfoLine('DSP Pipeline',
              AudioEngine.isAndroid ? 'Android DSP' : 'Web / Fallback'),
          _InfoLine('Virtualizer',
              AudioEngine.virtualizerSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
          _InfoLine('BassBoost',
              AudioEngine.bassBoostSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
          _InfoLine('PresetReverb',
              AudioEngine.reverbSupported ? 'Didukung ✓' : 'Tidak tersedia ✗'),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String val;
  const _InfoLine(this.label, this.val);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: Color(0xFF8E8E93), fontSize: 12)),
          Expanded(
            child: Text(val,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _EffectStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Efek Aktif',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.spatialAudio,
            builder: (_, v, __) =>
                _InfoLine('Spatial', v ? 'ON (${AudioEffectsService.spatialStrength.value})' : 'OFF'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.audioNormalize,
            builder: (_, v, __) => _InfoLine('Normalize', v ? 'ON' : 'OFF'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.bassBoost,
            builder: (_, v, __) => _InfoLine('BassBoost', '$v / 1000'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: AudioEffectsService.reverbPreset,
            builder: (_, v, __) => _InfoLine(
                'Reverb', AudioEffectsService.reverbPresetNames[v]),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, v, __) => ValueListenableBuilder<int>(
              valueListenable: AudioEffectsService.roomPreset,
              builder: (_, r, __) => _InfoLine(
                  'EQ',
                  v
                      ? '${AudioEffectsService.roomPresets[r]['name']} (room)'
                      : 'OFF'),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AudioEffectsService.playbackSpeed,
            builder: (_, v, __) => _InfoLine('Speed', '${v.toStringAsFixed(2)}x'),
          ),
        ],
      ),
    );
  }
}
