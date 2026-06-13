import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/themes/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: ThemeController.glassTheme,
        builder: (context, isGlass, _) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
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
                          bottom: 12,
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
                                  color: Colors.white,
                                ),
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
                            child: Container(color: const Color(0xFF48484A)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SettingsSectionHeader('TAMPILAN'),
                      const SizedBox(height: 8),
                      _SettingsGroup(
                        isGlass: isGlass,
                        children: [
                          _SettingsToggleRow(
                            icon: CupertinoIcons.drop_fill,
                            iconColor: const Color(0xFF30D158),
                            title: 'Liquid Glass',
                            subtitle: 'Blur & chromatic pada navigasi',
                            value: isGlass,
                            onChanged: ThemeController.setGlassTheme,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const _SettingsSectionHeader('TENTANG'),
                      const SizedBox(height: 8),
                      _SettingsGroup(
                        isGlass: isGlass,
                        children: [
                          const _SettingsInfoRow(
                            icon: CupertinoIcons.info_circle_fill,
                            iconColor: Color(0xFF0A84FF),
                            title: 'Versi',
                            trailing: '1.0.0',
                          ),
                          const _SettingsDivider(),
                          const _SettingsInfoRow(
                            icon: CupertinoIcons.music_note_2,
                            iconColor: Color(0xFFF92D48),
                            title: 'Music Player',
                            trailing: '© 2026',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  final String text;
  const _SettingsSectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final bool isGlass;

  const _SettingsGroup({required this.children, required this.isGlass});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(13);

    if (isGlass) {
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 0.8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0x44FF2D55),
                      const Color(0x55FFFFFF),
                      const Color(0x442979FF),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: radius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 56),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Color(0xFF38383A),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF30D158),
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String trailing;

  const _SettingsInfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(
        icon,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}
