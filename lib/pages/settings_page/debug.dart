part of '../settings_page.dart';

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
                color: const Color(0xFFF92D48).withValues(alpha: 0.15),
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
          builder: (_, idx, _) => _NotifIconRow(selectedIdx: idx),
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
