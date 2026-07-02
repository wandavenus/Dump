part of '../settings_page.dart';

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _DebugState.enabled,
      builder: (_, debug, _) => ValueListenableBuilder<PlaybackEngineType>(
        valueListenable: AudioEngineManager.activeEngineType,
        builder: (_, engine, _) {
          final isMedia3 = engine == PlaybackEngineType.media3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const _AppearanceSection(),

              // ── Audio / MediaKit Audio ─────────────────────────────────────
              // Dua section ini saling eksklusif dan bergantian dengan animasi.
              _AnimatedSection(
                visible: isMedia3,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 32),
                    _AudioSection(),
                  ],
                ),
              ),
              _AnimatedSection(
                visible: !isMedia3,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 32),
                    _MediaKitAudioSection(),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const _PlaybackEngineSection(),

              // ── Spatial & Equalizer (Media3 saja) ─────────────────────────
              _AnimatedSection(
                visible: isMedia3,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 32),
                    _SpatialSection(),
                    SizedBox(height: 32),
                    _EqualizerSection(),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const _SystemSection(),
              const SizedBox(height: 32),
              if (debug) ...[
                const _DebugSection(),
                const SizedBox(height: 32),
              ],
              const _AboutSection(),
              const SizedBox(height: 48),
            ],
          );
        },
      ),
    );
  }
}

// ─── Animated Section ─────────────────────────────────────────────────────────
//
// Widget wrapper yang menganimasikan visibilitas suatu section dengan dua
// animasi simultan:
//   • SizeTransition — tinggi section mengembang / mengempis (vertikal)
//   • FadeTransition — opacity 0 → 1 saat muncul, 1 → 0 saat hilang
//
// Widget ini SELALU ada di widget tree (tidak dikondisikan dengan `if`),
// sehingga state AnimationController-nya tetap hidup meski engine berganti
// dan tidak terjadi disposisi/init ulang yang tidak perlu.

class _AnimatedSection extends StatefulWidget {
  const _AnimatedSection({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_AnimatedSection> createState() => _AnimatedSectionState();
}

class _AnimatedSectionState extends State<_AnimatedSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      // Mulai langsung di posisi akhir tanpa animasi saat pertama kali render.
      value: widget.visible ? 1.0 : 0.0,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(_AnimatedSection old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      if (widget.visible) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _anim,
      axisAlignment: -1.0, // kembang dari atas
      child: FadeTransition(
        opacity: _anim,
        child: widget.child,
      ),
    );
  }
}
