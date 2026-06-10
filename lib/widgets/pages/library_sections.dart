import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class LibraryContent extends StatelessWidget {
  const LibraryContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: const [
            _LibraryHeader(),
            Divider(color: Color(0xFF38383A), thickness: 0.5, height: 0),
            SizedBox(height: 9),
            LibraryRow(icon: CupertinoIcons.music_note_list, title: 'Daftar Putar'),
            LibraryRow(icon: CupertinoIcons.mic, title: 'Artis'),
            LibraryRow(icon: CupertinoIcons.square_stack, title: 'Album'),
            LibraryRow(icon: CupertinoIcons.music_note, title: 'Lagu', routeName: '/musiclist'),
            LibraryRow(icon: CupertinoIcons.tv, title: 'TV & Film'),
          ],
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Perpustakaan',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: GestureDetector(
              onTap: () {},
              child: const Text('Edit',
                  style: TextStyle(color: Color(0xFFF92D48), fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final row = Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFF92D48), size: 28),
              const SizedBox(width: 11),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
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
