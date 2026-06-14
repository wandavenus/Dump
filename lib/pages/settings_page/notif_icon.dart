part of '../settings_page.dart';

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
