---
name: Search keyboard fix
description: Keyboard di SearchPage hanya muncul saat user tap search bar; tidak autofocus saat tab switch.
---

## Masalah
Keyboard muncul otomatis saat berpindah tab ke halaman Search, bukan hanya saat user mengetuk field input.

## Solusi
1. `TextField` di `_SearchBar` set `autofocus: false`
2. Bungkus container search bar dengan `GestureDetector(onTap: () => focusNode.requestFocus())`
3. Tambahkan `onTapOutside: (_) => focusNode.unfocus()` pada TextField
4. Override `deactivate()` di `_SearchSliversState` → `_focusNode.unfocus()`
5. `AutomaticKeepAliveClientMixin.wantKeepAlive = false` agar state tidak dipertahankan saat tab switch

**Why:** Flutter's FocusNode dapat mempertahankan fokus antar route/tab navigation. `deactivate()` adalah hook yang tepat untuk dismiss keyboard saat widget keluar dari tree.
