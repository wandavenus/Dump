part of '../settings_page.dart';

// ─── Laporkan Bug ───────────────────────────────────────────────────────────

class BugReportPage extends StatefulWidget {
  const BugReportPage({super.key});

  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends State<BugReportPage> {
  final _scroll = ScrollController();
  double _offset = 0;

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  Future<void> _openGmail() async {
    final uri = Uri.parse(
      'mailto:wandavenus25@gmail.com'
      '?subject=Bug%20Report%20%2F%20Saran%20Music%20Player',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
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
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Laporkan Bug',
        scrollOffset: _offset,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
        children: [
          const LargePageTitle(title: 'Laporkan Bug'),
          const SizedBox(height: 24),

          // ── Paragraf 1 ─────────────────────────────────────────────────
          const Text(
            'Kalau kamu menemukan bug, error, crash, atau ada fitur yang tidak bekerja sebagaimana mestinya, mohon laporkan agar bisa segera diperbaiki.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Paragraf 2 ─────────────────────────────────────────────────
          const Text(
            'Kamu juga bisa mengirimkan saran, masukan, atau permintaan fitur baru. Setiap laporan sangat membantu dalam meningkatkan kualitas aplikasi.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // ── Terima kasih ───────────────────────────────────────────────
          const Text(
            'Terima kasih atas dukunganmu.',
            style: TextStyle(
              color: Color(0xFFEBEBF0),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 36),

          // ── Kirim laporan ──────────────────────────────────────────────
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
                    onTap: _openGmail,
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
                    text:
                        ' atau ke akun sosial media di halaman Tentang.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
