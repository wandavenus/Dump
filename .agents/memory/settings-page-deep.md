---
name: Settings Page Deep Map
description: Every file in lib/pages/settings/ and shared settings widgets with class and role.
---

# Settings Page — Deep Map

## lib/pages/settings_page/ (root)

| File | Class(es) | Role |
|------|-----------|------|
| `settings_page.dart` | `SettingsPage` | Main settings root; debug section via 3× version tap in 2s |
| `changelog_data.dart` | `_changelogEntries` (const list) | Version history shown in Settings; bump here on every version release |
| `settings_widgets.dart` | `SettingsToggleRow`, `SettingsSliderRow`, `SettingsActionRow`, `_InfoLine`, `_GlassSubToggle` + others | Shared reusable settings row widgets |

## lib/pages/settings/ (subpages)

| File | Class | Role |
|------|-------|------|
| `equalizer_page/page.dart` | `EqualizerPage` | 32-band graphic EQ UI; drives system `Equalizer` (sole Band EQ backend); mutual-exclusion with Bit-Perfect mode; sample-rate sync |
| `sleep_timer_page/page.dart` | `SleepTimerPage` | Sleep timer configuration; delegates to `SleepTimerService` |
| `settings_widgets/action.dart` | `SettingsActionRow` | Clickable settings row for executing actions |

## Shared Widget Components

| Widget | Role |
|--------|------|
| `SettingsToggleRow` | Toggle switch row with label + optional subtitle |
| `SettingsSliderRow` | Slider row with label + value display |
| `SettingsActionRow` | Tappable action row (navigate or execute) |
| `_InfoLine` | Read-only info display row |
| `_GlassSubToggle` | Sub-toggle with glass/frosted style; part of ThemeController per-component toggles |

## ThemeController Sub-Toggles (9 components)
`glassTheme` = master switch; individual toggles: NavBar, AppBar, MiniPlayer, AlbumCard, ArtistCard, LibraryBar, SearchBar, Settings

## Important Settings Rules
- **Bit-Perfect mode**: master audio-bypass switch in Settings root (not inside Equalizer)
- **EQ + Bit-Perfect**: mutual exclusion — Bit-Perfect forces EQ off
- **ReplayGain + Loudness Norm**: mutual exclusion — cannot be active simultaneously
- **System EQ only**: native PEQ removed; don't reintroduce dual-EQ
- **Debug mode**: 3× tap version area in 2s → debug section (notif icon picker, effect status, audio session info)
- **Library edit mode**: `ReorderableListView` when `_editMode=true`; order persisted in SharedPrefs key `'library_item_order'`
