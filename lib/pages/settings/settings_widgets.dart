import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

// ─── Section Header ───────────────────────────────────────────────────────────

class SettingsSectionHeader extends StatelessWidget {
  final String text;
  const SettingsSectionHeader(this.text, {super.key});

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

// ─── Divider ──────────────────────────────────────────────────────────────────

class SettingsDivider extends StatelessWidget {
  final double indent;
  const SettingsDivider({super.key, this.indent = 16});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      color: const Color(0xFF38383A),
      indent: indent,
      endIndent: 0,
    );
  }
}

// ─── Toggle Row ───────────────────────────────────────────────────────────────

class SettingsToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const SettingsToggleRow({
    super.key,
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
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 12),
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

// ─── Slider Row ───────────────────────────────────────────────────────────────

class SettingsSliderRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Future<void> Function(double) onChanged;
  final bool showReset;
  final VoidCallback? onReset;

  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions = 20,
    this.showReset = false,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              if (showReset && onReset != null)
                GestureDetector(
                  onTap: onReset,
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                        color: Color(0xFFF92D48), fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFF92D48),
              thumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF48484A),
              overlayColor: const Color(0x29F92D48),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => onChanged(v),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────

class SettingsInfoRow extends StatelessWidget {
  final String title;
  final String trailing;

  const SettingsInfoRow({
    super.key,
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
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Action Row ───────────────────────────────────────────────────────────────

class SettingsActionRow extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback onTap;
  final bool isDestructive;

  const SettingsActionRow({
    super.key,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDestructive
                      ? const Color(0xFFF92D48)
                      : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              trailing,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
            ),
            if (trailing.isNotEmpty) const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }
}
