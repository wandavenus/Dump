part of '../library_sections.dart';

class _EditableRow extends StatelessWidget {
  const _EditableRow({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            children: [
              // Drag handle
              const Icon(Icons.drag_handle, color: Color(0xFF8E8E93), size: 22),
              const SizedBox(width: 6),
              Icon(icon, color: const Color(0xFFF92D48), size: 28),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
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
  }
}
