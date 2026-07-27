part of '../settings_page.dart';

// ─── Laporkan Bug ───────────────────────────────────────────────────────────

class BugReportPage extends StatelessWidget {
  const BugReportPage({super.key});

  Future<void> _openGmail(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:wandavenus25@gmail.com'
      '?subject=Bug%20Report%20%2F%20Saran%20Music%20Player',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        final c = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cantOpenEmail),
            backgroundColor: c.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        title: Text(
          context.l10n.bugReportTitle,
          style: TextStyle(
            color: c.primaryLabel,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: c.separator),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── Paragraf 1 ───────────────────────────────────────────────────
          Text(
            context.l10n.bugReportParagraph1,
            style: TextStyle(
              color: c.primaryLabel.withValues(alpha: 0.87),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Paragraf 2 ───────────────────────────────────────────────────
          Text(
            context.l10n.bugReportParagraph2,
            style: TextStyle(
              color: c.primaryLabel.withValues(alpha: 0.87),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Terima kasih ─────────────────────────────────────────────────
          Text(
            context.l10n.thankYouSupport,
            style: TextStyle(
              color: c.primaryLabel.withValues(alpha: 0.87),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 36),

          // ── Kirim laporan ────────────────────────────────────────────────
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: c.secondaryLabel,
                fontSize: 15,
                height: 1.6,
              ),
              children: [
                TextSpan(text: '${context.l10n.sendReportGmail} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => _openGmail(context),
                    child: const Text(
                      'wandavenus25@gmail.com',
                      style: TextStyle(
                        color: Color(0xFFF92D48),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                TextSpan(
                  text: ' ${context.l10n.orSocialMedia}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
