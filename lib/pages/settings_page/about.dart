part of '../settings_page.dart';

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.sectionAbout),
        const SizedBox(height: 6),
        SettingsActionRow(
          title: l.reportBug,
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const BugReportPage()),
          ),
        ),
        SettingsActionRow(
          title: l.support,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (sheetCtx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GestureDetector(
                    onTap: () => _confirmSaveQris(sheetCtx),
                    child: Image.asset(
                      'assets/images/qris_support.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SettingsActionRow(
          title: l.aboutApp,
          onTap: () => Navigator.of(context).push(
            ZoomFadeRoute<void>(page: const AboutAppPage()),
          ),
        ),
        const SettingsDivider(),
        const _AboutFooter(),
      ],
    );
  }
}

Future<void> _confirmSaveQris(BuildContext context) async {
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: const Text('Simpan QR Code'),
      content: const Text('Simpan gambar QRIS ke galeri?'),
      actions: [
        CupertinoDialogAction(
          isDestructiveAction: false,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    final bytes = await rootBundle.load('assets/images/qris_support.webp');
    await Gal.putImageBytes(
      bytes.buffer.asUint8List(),
      name: 'qris_wndavenz',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gambar berhasil disimpan ke galeri')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan gambar')),
      );
    }
  }
}

class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  static final int _currentYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final year = _currentYear;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l.madeByShort} Wndavenznchole',
              textAlign: TextAlign.left,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.copyrightFooter(year),
              textAlign: TextAlign.left,
              style: TextStyle(
                color: AppColors.of(context).secondaryLabel,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
