part of '../settings_widgets.dart';

class SettingsActionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const SettingsActionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDestructive
                      ? const Color(0xFFF92D48)
                      : c.primaryLabel,
                  fontSize: 16,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(color: c.secondaryLabel, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
