import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Data model tiap menu library ─────────────────────────────────────────────

class _LibraryItem {
  final String id;
  final IconData icon;
  final String title;
  final String? routeName;

  const _LibraryItem({
    required this.id,
    required this.icon,
    required this.title,
    this.routeName,
  });
}

// Daftar default (urutan awal)
const _defaultItems = <_LibraryItem>[
  _LibraryItem(id: 'playlist', icon: CupertinoIcons.music_note_list, title: 'Daftar Putar'),
  _LibraryItem(id: 'artist',   icon: CupertinoIcons.mic,             title: 'Artis'),
  _LibraryItem(id: 'album',    icon: CupertinoIcons.square_stack,    title: 'Album'),
  _LibraryItem(id: 'songs',    icon: CupertinoIcons.music_note,      title: 'Lagu',      routeName: '/musiclist'),
  _LibraryItem(id: 'tv',       icon: CupertinoIcons.tv,              title: 'TV & Film'),
];

const _kOrderKey = 'library_item_order';

// ─── LibraryContent ────────────────────────────────────────────────────────────

class LibraryContent extends StatefulWidget {
  const LibraryContent({super.key});

  @override
  State<LibraryContent> createState() => _LibraryContentState();
}

class _LibraryContentState extends State<LibraryContent> {
  bool _editMode = false;
  List<_LibraryItem> _items = List.of(_defaultItems);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kOrderKey);
    if (saved != null && saved.length == _defaultItems.length) {
      final ordered = saved
          .map((id) =>
              _defaultItems.firstWhere((e) => e.id == id,
                  orElse: () => _defaultItems.first))
          .toList();
      if (mounted) setState(() => _items = ordered);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOrderKey, _items.map((e) => e.id).toList());
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    _saveOrder();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _LibraryHeader(
              editMode: _editMode,
              onToggleEdit: () => setState(() => _editMode = !_editMode),
            ),
            const Divider(color: Color(0xFF38383A), thickness: 0.5, height: 0),
            const SizedBox(height: 9),
            _editMode ? _buildReorderable() : _buildStaticList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticList() {
    return Column(
      children: _items
          .map((item) => _LibraryRow(
                key: ValueKey(item.id),
                icon: item.icon,
                title: item.title,
                routeName: item.routeName,
              ))
          .toList(),
    );
  }

  Widget _buildReorderable() {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: ScaleTransition(
          scale: animation.drive(
            Tween<double>(begin: 1, end: 1.04).chain(
              CurveTween(curve: Curves.easeOut),
            ),
          ),
          child: child,
        ),
      ),
      onReorder: _onReorder,
      children: _items
          .map((item) => _EditableRow(
                key: ValueKey(item.id),
                icon: item.icon,
                title: item.title,
              ))
          .toList(),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────

class _LibraryHeader extends StatelessWidget {
  final bool editMode;
  final VoidCallback onToggleEdit;

  const _LibraryHeader({
    required this.editMode,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Perpustakaan',
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: GestureDetector(
              onTap: onToggleEdit,
              child: Text(
                editMode ? 'Selesai' : 'Edit',
                style: TextStyle(
                  color: editMode
                      ? Colors.white.withOpacity(0.7)
                      : const Color(0xFFF92D48),
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Row Normal ────────────────────────────────────────────────────────────────

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

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    super.key,
    required this.icon,
    required this.title,
  });

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
              const Icon(
                Icons.drag_handle,
                color: Color(0xFF8E8E93),
                size: 22,
              ),
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
