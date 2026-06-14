---
name: Library edit mode
description: LibraryContent StatefulWidget dengan ReorderableListView saat edit mode; urutan disimpan SharedPrefs.
---

## State
```dart
bool _editMode = false;
List<_LibraryItem> _items = List.of(_defaultItems);
```

## Item model
```dart
class _LibraryItem {
  final String id;       // 'playlist', 'artist', 'album', 'songs', 'tv'
  final IconData icon;
  final String title;
  final String? routeName;
}
```

## Persist
```dart
const _kOrderKey = 'library_item_order';
// Save: prefs.setStringList(_kOrderKey, _items.map((e) => e.id).toList())
// Load: prefs.getStringList(_kOrderKey) → reorder _defaultItems
```

## Edit vs Normal view
- **Normal**: Column of `_LibraryRow` widgets (tappable, shows chevron)
- **Edit**: `ReorderableListView(shrinkWrap: true, physics: NeverScrollableScrollPhysics)` of `_EditableRow` (shows drag handle, no tap)
- `_LibraryHeader` shows "Edit" (merah) atau "Selesai" (putih redup) tergantung state

## proxyDecorator
Scale 1→1.04 saat drag untuk feedback visual tanpa Material elevation artifact.

**Why:** ReorderableListView harus `shrinkWrap + NeverScrollablePhysics` karena dibungkus SingleChildScrollView; jika tidak, terjadi infinite height error.
