part of '../library_sections.dart';

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    super.key,
    required this.icon,
    required this.title,
    this.routeName,
  });

  final IconData icon;
  final String title;
  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final row = Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFF92D48), size: 28),
              const SizedBox(width: 11),
              Expanded(
                child: Text(title,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 18)),
              ),
              
            ],
          ),
        ),
        const Divider(
          color: Color(0xFF38383A),
          thickness: 0.5,
          indent: 38,
          endIndent: 0,
        ),
      ],
    );

    if (routeName == null) return row;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, routeName!),
      child: row,
    );
  }
}

// ─── Row dalam mode Edit (dengan drag handle) ──────────────────────────────────
