part of '../settings_page.dart';

// ─── TENTANG ─────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('TENTANG'),
        const SizedBox(height: 6),
        const SettingsInfoRow(title: 'Music Player', trailing: 'Wndavenznchole'),
        const SettingsDivider(),
        // Version — tap 3x to enable debug mode
        _VersionTile(),
        const SettingsDivider(),
      ],
    );
  }
}

class _VersionTile extends StatefulWidget {
  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  int _tapCount = 0;
  DateTime? _firstTap;

  void _onTap() {
    final now = DateTime.now();
    if (_firstTap == null ||
        now.difference(_firstTap!) > const Duration(seconds: 2)) {
      _firstTap = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }

    if (_tapCount >= 3) {
      _tapCount = 0;
      _firstTap = null;
      if (!_DebugState.enabled.value) {
        _DebugState.enabled.value = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mode Debug diaktifkan'),
            backgroundColor: Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<bool>(
        valueListenable: _DebugState.enabled,
        builder: (_, debug, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Versi',
                  style: TextStyle(
                    color: debug ? const Color(0xFFF92D48) : Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                debug ? '1.0.0 [DEBUG]' : '1.0.0',
                style: const TextStyle(
                    color: Color(0xFF8E8E93), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
