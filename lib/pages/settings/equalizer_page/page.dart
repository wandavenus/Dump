part of '../equalizer_page.dart';

// ─── EqualizerPage ─────────────────────────────────────────────────────────────

class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        title: 'Equalizer',
        scrollOffset: 100,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AudioEffectsService.equalizerEnabled,
            builder: (_, enabled, _) => CupertinoSwitch(
              value: enabled,
              onChanged: AudioEffectsService.setEqualizerEnabled,
              activeTrackColor: const Color(0xFFF92D48),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8),
              _EqPresetChips(),
              _EqBandSliderSection(),
              _SectionDivider(),
              _ReverbSection(),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable section divider ─────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Divider(color: Color(0xFF2C2C2E), height: 1),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
