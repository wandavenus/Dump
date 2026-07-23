part of '../settings_page.dart';

// ─── URL konstanta ────────────────────────────────────────────────────────────

const String _kInstagramUrl = 'https://www.instagram.com/wndavenznchole';
const String _kFacebookUrl  = 'https://www.facebook.com/Wndavenznchole';

// ─── Tentang App ────────────────────────────────────────────────────────────

class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  // Year is constant for the lifetime of the widget — computed once so
  // build() never allocates a DateTime on every frame.
  static final int _currentYear = DateTime.now().year;

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
    if (_tapCount >= 3) {
      _tapCount = 0;
      _firstTap = null;
      if (!_DebugState.enabled.value) {
        _DebugState.enabled.value = true;
        final c = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Mode Debug aktif'),
            backgroundColor: c.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        final c = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tidak bisa membuka link'),
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
    final year = _currentYear;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        title: 'Tentang App',
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
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
          // ── Konten ──────────────────────────────────────────────────────
          CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nama app
                        Text(
                          'Music Player',
                          style: TextStyle(
                            color: c.primaryLabel,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Versi — tap 3× untuk mode debug
                        ValueListenableBuilder<bool>(
                          valueListenable: _DebugState.enabled,
                          builder: (_, debug, _) => GestureDetector(
                            onTap: _onVersionTap,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 4),
                              child: Text(
                                debug
                                    ? 'Versi 1.1.5 [Mode Debug Aktif]'
                                    : 'Versi 1.1.5',
                                style: TextStyle(
                                  color: debug
                                      ? const Color(0xFFF92D48)
                                      : c.secondaryLabel,
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
                          color: c.subtleSeparator,
                        ),
                        const SizedBox(height: 28),

                        // Dibuat oleh
                        Text(
                          'Dibuat dengan dedikasi oleh',
                          style: TextStyle(
                            color: c.primaryLabel.withValues(alpha: 0.87),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Wndavenznchole',
                          style: TextStyle(
                            color: c.primaryLabel,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Deskripsi singkat ──────────────────────────
                        Text(
                          'Pemutar musik offline berbasis Flutter dengan sistem Audio Native Media3 Dual Exoplayer + Single Exoplayer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.secondaryLabel,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Catatan Pembaruan ──────────────────────────
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            ZoomFadeRoute<void>(page: const ChangelogPage()),
                          ),
                          child: const Text(
                            'Catatan Pembaruan',
                            style: TextStyle(
                              color: Color(0xFFF92D48),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Sosial media ───────────────────────────────
                        _SocialRow(
                          icon: FontAwesomeIcons.instagram,
                          label: 'Wndavenznchole',
                          onTap: () => _openUrl(_kInstagramUrl),
                        ),
                        const SizedBox(height: 14),
                        _SocialRow(
                          icon: FontAwesomeIcons.facebook,
                          label: 'Wndavenz Nchole',
                          onTap: () => _openUrl(_kFacebookUrl),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Footer copyright ─────────────────────────────────────────────
          Positioned(
            bottom: bottomPadding + 20,
            left: 0,
            right: 0,
            child: Text(
              '© $year Flutter Music App with Media3 Exoplayer',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.tertiaryLabel,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget baris sosmed ────────────────────────────────────────────────────

class _SocialRow extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, color: c.primaryLabel, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: c.primaryLabel,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
