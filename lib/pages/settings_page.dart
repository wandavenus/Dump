import 'dart:ui';
import 'package:flutter/material.dart';

import '../themes/liquid_glass.dart';
import '../themes/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.allGlass,
      builder: (context, _) {
        final isGlass = ThemeController.glassTheme.value;
        return Scaffold(
          backgroundColor: isGlass ? Colors.transparent : Colors.black,
          appBar: _buildAppBar(isGlass),
          body: _SettingsBody(isGlass: isGlass),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool isGlass) {
    return AppBar(
      backgroundColor: isGlass ? Colors.transparent : Colors.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      flexibleSpace: isGlass ? const LiquidGlassBar(showBottomBorder: true) : null,
      title: const Text(
        'Pengaturan',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      centerTitle: true,
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.isGlass});

  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // ── Header banner glass ──────────────────────────────────────────
        _GlassBanner(isGlass: isGlass),
        const SizedBox(height: 24),

        // ── Seksi Tampilan ───────────────────────────────────────────────
        _SectionLabel(label: 'TAMPILAN', isGlass: isGlass),
        const SizedBox(height: 8),
        _MasterGlassToggle(isGlass: isGlass),

        // Komponen per-tombol — animasi expand/collapse
        _PerComponentSection(isGlass: isGlass),
        const SizedBox(height: 24),

        // ── Seksi Tentang ────────────────────────────────────────────────
        _SectionLabel(label: 'TENTANG', isGlass: isGlass),
        const SizedBox(height: 8),
        _GlassListTile(
          isGlass: isGlass,
          icon: Icons.info_outline_rounded,
          title: 'Versi Aplikasi',
          trailing: const Text('1.0.0',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
        ),
        _GlassListTile(
          isGlass: isGlass,
          icon: Icons.music_note_rounded,
          title: 'Music Player',
          subtitle: 'Dibuat dengan Flutter',
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Banner glass / solid header
// ──────────────────────────────────────────────────────────────────────────────

class _GlassBanner extends StatelessWidget {
  const _GlassBanner({required this.isGlass});
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    if (!isGlass) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.blur_on_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Liquid Glass',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('Tema kaca bening iOS 27',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.35),
                    Colors.white.withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.white.withOpacity(0.30), width: 0.6),
              ),
              child: const Icon(Icons.blur_on_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Liquid Glass',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('Tema kaca bening iOS 27 aktif',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Label seksi
// ──────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isGlass});
  final String label;
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: isGlass ? Colors.white60 : Colors.white38,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Master toggle Liquid Glass
// ──────────────────────────────────────────────────────────────────────────────

class _MasterGlassToggle extends StatelessWidget {
  const _MasterGlassToggle({required this.isGlass});
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: isGlass
          ? LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              addShadow: true,
              child: _switchTile(),
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _switchTile(),
            ),
    );
  }

  Widget _switchTile() {
    return SwitchListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: const Icon(Icons.blur_on_rounded, color: Colors.white70),
      title: const Text('Liquid Glass',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500)),
      subtitle: Text(
        'Efek kaca bening di seluruh aplikasi',
        style: TextStyle(
            color: isGlass ? Colors.white60 : Colors.white38,
            fontSize: 13),
      ),
      value: isGlass,
      activeColor: const Color(0xFFF92D48),
      onChanged: (v) => ThemeController.setGlassTheme(v),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Seksi per-komponen — expand/collapse
// ──────────────────────────────────────────────────────────────────────────────

class _PerComponentSection extends StatelessWidget {
  const _PerComponentSection({required this.isGlass});
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: isGlass
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'KOMPONEN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: Colors.white60,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LiquidGlass(
                    borderRadius: BorderRadius.circular(16),
                    padding: EdgeInsets.zero,
                    addShadow: false,
                    child: Column(
                      children: [
                        _ComponentSwitch(
                          icon: Icons.navigation_rounded,
                          title: 'Nav Bar',
                          subtitle: 'Bar navigasi bawah',
                          notifier: ThemeController.glassNavBar,
                          onChanged: ThemeController.setGlassNavBar,
                          showDivider: true,
                        ),
                        _ComponentSwitch(
                          icon: Icons.web_asset_rounded,
                          title: 'App Bar',
                          subtitle: 'Bilah judul atas',
                          notifier: ThemeController.glassAppBar,
                          onChanged: ThemeController.setGlassAppBar,
                          showDivider: true,
                        ),
                        _ComponentSwitch(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'Mini Player',
                          subtitle: 'Player mini bawah',
                          notifier: ThemeController.glassMiniPlayer,
                          onChanged: ThemeController.setGlassMiniPlayer,
                          showDivider: true,
                        ),
                        _ComponentSwitch(
                          icon: Icons.grid_view_rounded,
                          title: 'Kartu Lagu',
                          subtitle: 'Card di carousel & grid',
                          notifier: ThemeController.glassCards,
                          onChanged: ThemeController.setGlassCards,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

class _ComponentSwitch extends StatelessWidget {
  const _ComponentSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.notifier,
    required this.onChanged,
    required this.showDivider,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ValueNotifier<bool> notifier;
  final Future<void> Function(bool) onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (ctx, value, _) {
        return Column(
          children: [
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              secondary: Icon(icon, color: Colors.white60, size: 22),
              title: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
              value: value,
              activeColor: const Color(0xFFF92D48),
              onChanged: onChanged,
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                    height: 0,
                    thickness: 0.5,
                    color: Colors.white.withOpacity(0.12)),
              ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// List tile glass-aware
// ──────────────────────────────────────────────────────────────────────────────

class _GlassListTile extends StatelessWidget {
  const _GlassListTile({
    required this.isGlass,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final bool isGlass;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(icon, color: Colors.white60),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(color: Colors.white54, fontSize: 13))
          : null,
      trailing: trailing,
      onTap: onTap,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: isGlass
          ? LiquidGlass(
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              addShadow: false,
              child: tile,
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: tile,
            ),
    );
  }
}
