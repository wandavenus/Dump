import 'package:flutter/material.dart';

class CommonActions extends StatelessWidget {
  const CommonActions({super.key});

  void _cast(BuildContext context) {
    // TODO: Cast function
  }

  void _more(BuildContext context) {
    PopupMenuButton<String>(
  icon: const Icon(
    Icons.more_vert,
    color: Color(0xFFF92D48),
    size: 24,
  ),
  onSelected: (value) {
    if (value == 'settings') {
      Navigator.pushNamed(context, '/settings');
    }
  },
  itemBuilder: (context) => [
    const PopupMenuItem(
      value: 'settings',
      child: Text('Pengaturan'),
    ),
  ],
)
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -0.0),
          child: IconButton(
            onPressed: () => _cast(context),
            icon: const Icon(Icons.cast),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -0.0),
          child: IconButton(
            onPressed: () => _more(context),
            icon: const Icon(Icons.more_vert),
          ),
        ),
      ],
    );
  }
}