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
          onTap: () => Navigator.of(
            context,
          ).push(ZoomFadeRoute<void>(page: const BugReportPage())),
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
                    // pageContext = context dari halaman settings (bukan sheetCtx)
                    // agar SnackBar muncul di Scaffold yang benar.
                    onTap: () =>
                        _confirmSaveQris(sheetCtx, pageContext: context),
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
          onTap: () => Navigator.of(
            context,
          ).push(ZoomFadeRoute<void>(page: const AboutAppPage())),
        ),
        const SettingsDivider(),
        const _AboutFooter(),
      ],
    );
  }
}

/// Menampilkan dialog konfirmasi lalu menyimpan QRIS ke galeri.
///
/// [context]     — context bottom sheet (untuk dialog Cupertino).
/// [pageContext] — context halaman Settings (untuk SnackBar & Scaffold).
Future<void> _confirmSaveQris(
  BuildContext context, {
  required BuildContext pageContext,
}) async {
  const tag = 'QrisSave';
  // Ambil l10n dari halaman Settings (bukan sheet) agar konsisten dan tetap
  // valid sepanjang alur dialog + snackbar, termasuk setelah async gap.
  final l = pageContext.l10n;

  // ── Dialog konfirmasi ──────────────────────────────────────────────────────
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: Text(l.qrisSaveTitle),
      content: Text(l.qrisSavePrompt),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.save),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // ── Helper snackbar (selalu pakai pageContext) ─────────────────────────────
  void showSnack(String message) {
    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  File? tempFile;
  try {
    // ── 1. Cek & minta izin galeri ─────────────────────────────────────────
    LogService.log(tag, 'Checking gallery access…');
    if (!await Gal.hasAccess()) {
      LogService.log(tag, 'No access — requesting…');
      final granted = await Gal.requestAccess();
      if (!granted) {
        LogService.log(
          tag,
          'Permission denied by user',
          level: LogLevel.warning,
        );
        showSnack(l.qrisGalleryDenied);
        return;
      }
    }
    LogService.log(tag, 'Permission granted');

    // ── 2. Load asset & validasi ───────────────────────────────────────────
    LogService.log(tag, 'Loading asset qris_support.webp…');
    final byteData = await rootBundle.load('assets/images/qris_support.webp');
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    LogService.log(tag, 'Asset loaded — ${bytes.length} bytes');
    if (bytes.isEmpty) {
      throw Exception('Asset kosong (0 bytes)');
    }

    // ── 3. Tulis ke temporary file ─────────────────────────────────────────
    final tmpDir = await getTemporaryDirectory();
    tempFile = File('${tmpDir.path}/qris_wndavenz.webp');
    LogService.log(tag, 'Writing temp file: ${tempFile.path}');
    await tempFile.writeAsBytes(bytes, flush: true);

    // ── 4. Validasi temp file ──────────────────────────────────────────────
    final exists = tempFile.existsSync();
    final size = exists ? tempFile.lengthSync() : 0;
    LogService.log(tag, 'Temp file — exists=$exists size=$size');
    if (!exists || size <= 0) {
      throw Exception('Temp file tidak valid (exists=$exists size=$size)');
    }

    // ── 5. Simpan ke galeri via Gal.putImage ───────────────────────────────
    LogService.log(tag, 'Calling Gal.putImage…');
    await Gal.putImage(tempFile.path);
    LogService.log(tag, 'Gal.putImage() selesai — sukses');

    showSnack(l.qrisSavedToGallery);
  } on GalException catch (e, st) {
    // Tangani setiap tipe GalException secara spesifik
    final reason = switch (e.type) {
      GalExceptionType.accessDenied => l.qrisAccessDenied,
      GalExceptionType.notEnoughSpace => l.qrisNotEnoughSpace,
      GalExceptionType.notSupportedFormat => l.qrisFormatUnsupported,
      GalExceptionType.unexpected => l.qrisUnexpectedError,
    };
    LogService.error(
      tag,
      'GalException [${e.type.name}]: $e',
      stackTrace: st.toString(),
    );
    showSnack(l.qrisSaveFailed('$reason (${e.type.name})'));
  } on Object catch (e, st) {
    LogService.error(tag, 'Unexpected error: $e', stackTrace: st.toString());
    showSnack(l.qrisSaveFailed('$e'));
  } finally {
    // Hapus temp file setelah selesai (sukses maupun gagal)
    try {
      if (tempFile != null && tempFile.existsSync()) {
        await tempFile.delete();
        LogService.log(tag, 'Temp file dihapus');
      }
    } on Object catch (_) {}
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
