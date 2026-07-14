part of '../settings_page.dart';

// ─── Tentang App ────────────────────────────────────────────────────────────
//
// Tampilan minimalis: nama app + versi di tengah layar, footer copyright
// di bawah. Ketuk teks versi 5× dalam 2 detik untuk Mode Debug.

class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  final _scroll = ScrollController();
  double _offset = 0;

  // ── Debug easter egg ──────────────────────────────────────────────────────
  int _tapCount = 0;
  DateTime? _firstTap;

  void _onVersionTap() {
    final now = DateTime.now();
    if (_firstTap == null ||
        now.difference(_firstTap!) > const Duration(seconds: 2)) {
      _firstTap = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    if (_tapCount >= 5) {
      _tapCount = 0;
      _firstTap = null;
      if (!_DebugState.enabled.value) {
        _DebugState.enabled.value = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mode Debug aktif'),
            backgroundColor: Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
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

  void _onScroll() {
    final o = _scroll.offset;
    if ((o - _offset).abs() > 0.5) setState(() => _offset = o);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Tentang App',
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
      body: Stack(
        children: [
          // ── Konten tengah ───────────────────────────────────────────────
          LayoutBuilder(
            builder: (_, constraints) => SingleChildScrollView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Nama app
                    const Text(
                      'Music Player',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Versi — tap 5× untuk mode debug
                    ValueListenableBuilder<bool>(
                      valueListenable: _DebugState.enabled,
                      builder: (_, debug, _) => GestureDetector(
                        onTap: _onVersionTap,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 4),
                          child: Text(
                            debug ? 'Versi 1.0.0 [DEBUG]' : 'Versi 1.0.0',
                            style: TextStyle(
                              color: debug
                                  ? const Color(0xFFF92D48)
                                  : const Color(0xFF8E8E93),
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Divider pendek
                    Container(
                      width: 48,
                      height: 1,
                      color: const Color(0xFF3A3A3C),
                    ),
                    const SizedBox(height: 28),

                    // Dibuat oleh
                    const Text(
                      'Dibuat dengan dedikasi oleh',
                      style: TextStyle(
                        color: Color(0xFFEBEBF0),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Wndavenznchole',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    // Space bawah supaya footer tidak nutupin konten
                    const SizedBox(height: 72),
                  ],
                ),
              ),
            ),
          ),

          // ── Footer copyright ─────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  '© $year Flutter Music App × Apple Music',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF636366),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
