part of '../library_sections.dart';

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
      final ordered =
          saved
              .map(
                (id) => _defaultItems.firstWhere(
                  (e) => e.id == id,
                  orElse: () => _defaultItems.first,
                ),
              )
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
      children:
          _items
              .map(
                (item) => _LibraryRow(
                  key: ValueKey(item.id),
                  icon: item.icon,
                  title: item.title,
                  destination: item.destination,
                ),
              )
              .toList(),
    );
  }

  Widget _buildReorderable() {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      proxyDecorator:
          (child, index, animation) => Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: animation.drive(
                Tween<double>(
                  begin: 1,
                  end: 1.04,
                ).chain(CurveTween(curve: Curves.easeOut)),
              ),
              child: child,
            ),
          ),
      onReorder: _onReorder,
      children:
          _items
              .map(
                (item) => _EditableRow(
                  key: ValueKey(item.id),
                  icon: item.icon,
                  title: item.title,
                ),
              )
              .toList(),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────
