part of '../library_sections.dart';

class LibraryRow extends StatelessWidget {
  const LibraryRow({
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
    return _LibraryRow(icon: icon, title: title, routeName: routeName);
  }
}
