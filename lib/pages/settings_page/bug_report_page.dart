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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak bisa membuka aplikasi email'),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
        title: const Text(
          'Laporkan Bug',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: const Color(0xFF48484A)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── Paragraf 1 ───────────────────────────────────────────────────
          const Text(
            'Kalau kamu menemukan bug, error, crash, atau ada fitur yang tidak bekerja sebagaimana mestinya, mohon laporkan agar bisa segera diperbaiki.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Paragraf 2 ───────────────────────────────────────────────────
          const Text(
            'Kamu juga bisa mengirimkan saran, masukan, atau permintaan fitur baru. Setiap laporan sangat membantu dalam meningkatkan kualitas aplikasi.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Terima kasih ─────────────────────────────────────────────────
          const Text(
            'Terima kasih atas dukunganmu.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 36),

          // ── Kirim laporan ────────────────────────────────────────────────
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 15,
                height: 1.6,
              ),
              children: [
                const TextSpan(text: 'Kirim laporan kamu ke Gmail '),
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
                const TextSpan(
                  text: ' atau ke akun sosial media di halaman Tentang.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
