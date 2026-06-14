import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/models/lyrics_settings.dart';
import 'package:musicplayer/services/audio/audio_effects_service.dart';
import 'package:musicplayer/services/audio/audio_engine.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/services/sleep_timer_service.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'settings/settings_widgets.dart';
import 'settings/equalizer_page.dart';
import 'settings/sleep_timer_page.dart';

export 'settings/settings_widgets.dart';

part 'settings/settings_debug_state.dart';
part 'settings/appearance_section.dart';
part 'settings/audio_section.dart';
part 'settings/spatial_section.dart';
part 'settings/equalizer_section.dart';
part 'settings/sleep_timer_section.dart';
part 'settings/lyrics_section.dart';
part 'settings/audio_output_section.dart';
part 'settings/system_section.dart';
part 'settings/debug_section.dart';
part 'settings/about_section.dart';

// ─── Page ─────────────────────────────────────────────────────────────────────

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _SettingsAppBar(),
            SliverToBoxAdapter(child: _SettingsBody()),
          ],
        ),
      ),
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────

class _SettingsAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      pinned: true,
      expandedHeight: 100,
      collapsedHeight: kToolbarHeight,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final expandRatio = ((constraints.maxHeight - kToolbarHeight) /
                  (100 - kToolbarHeight))
              .clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Positioned(
                bottom: 13,
                left: 16,
                child: Opacity(
                  opacity: expandRatio,
                  child: Text(
                    'Pengaturan',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(expandRatio),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0),
                  child: const Center(
                    child: Text(
                      'Pengaturan',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 0.5,
                child: Opacity(
                  opacity: (1 - expandRatio).clamp(0.0, 1.0),
                  child: Container(color: const Color(0xFF38383A)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _SettingsBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _DebugState.enabled,
      builder: (_, debug, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const _AppearanceSection(),
          const SizedBox(height: 32),
          const _AudioSection(),
          const SizedBox(height: 32),
          const _SpatialSection(),
          const SizedBox(height: 32),
          const _EqualizerSection(),
          const SizedBox(height: 32),
          const _SleepTimerSection(),
          const SizedBox(height: 32),
          const _LyricsSection(),
          const SizedBox(height: 32),
          const _AudioOutputSection(),
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
      ),
    );
  }
}
