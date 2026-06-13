import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:musicplayer/themes/theme_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
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
                              child: Container(color: const Color(0xFF38383A)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const _SectionHeader('TAMPILAN'),
                      const SizedBox(height: 6),
                      _SettingsToggleRow(
                        title: 'Liquid Glass',
                        subtitle: 'Efek blur pada seluruh UI',
                        value: isGlass,
                        onChanged: ThemeController.setGlassTheme,
                      ),
                      const _SettingsDivider(),
                      const SizedBox(height: 32),
                      const _SectionHeader('TENTANG'),
                      const SizedBox(height: 6),
                      const _SettingsInfoRow(
                        title: 'Versi',
                        trailing: '1.0.0',
                      ),
                      const _SettingsDivider(),
                      const _SettingsInfoRow(
                        title: 'Music Player',
                        trailing: '© 2026',
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 0.5,
      thickness: 0.5,
      color: Color(0xFF38383A),
      indent: 16,
      endIndent: 0,
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
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
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFF92D48),
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  final String title;
  final String trailing;

  const _SettingsInfoRow({
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
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
