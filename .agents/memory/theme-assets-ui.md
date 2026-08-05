---
name: Theme, Assets & UI System
description: ThemeController fields, glass system, shader, assets tree (fonts/shaders/images), PaletteExtractor, UI constants.
---

# Theme, Assets & UI System

## ThemeController (`lib/themes/theme_controller.dart`)

All-static singleton (private constructor), persists via `SharedPreferences`.

**10 `ValueNotifier<bool>` fields:**

| Field | Scope |
|-------|-------|
| `glassTheme` | Master switch |
| `glassNavBar` | Bottom navigation bar |
| `glassAppBar` | App bar |
| `glassMiniPlayer` | Mini player strip |
| `glassPlayerSheet` | Expanded player sheet |
| `glassAlbumCard` | Album cards |
| `glassArtistCard` | Artist cards |
| `glassLibraryBar` | Library tab bar |
| `glassSearchBar` | Search bar |
| `glassSettings` | Settings page |

Components subscribe via `ValueListenableBuilder`. Helper: `isGlass(notifier)` checks master AND component toggle.

## Glass/Frosted UI Files

| File | Role |
|------|------|
| `lib/themes/glass_navbar.dart` | Implements `BackdropFilter` for glass nav bar |
| `lib/pages/settings_page/glass_toggle.dart` | Per-component toggle UI in settings |
| `lib/widgets/unified_morph_player.dart` | Glass morphing logic using ThemeController |

## Shader: fluid.frag

- Path: `assets/shaders/fluid.frag`
- Type: GLSL fragment shader
- Effect: Atmospheric colour-field / fluid effect for player background
- Rendered by: `lib/widgets/player/player_background/fog_painter.dart`
- Colors fed from: `NativePaletteService` primary/secondary/accent/highlight/shadow
- Pre-computed color vars: `_c0r…_c2b`; 256×512 canvas; `RepaintBoundary` isolates repaints
- Pauses via `TickerMode` when player collapsed

## NativePaletteService (`lib/services/native_palette_service.dart`)

- Android backend: `NativePaletteBridge.kt` using `androidx.palette:palette`
- Reads artwork by `songId` through `ArtworkCacheManager`; raw image bytes do not
  cross the MethodChannel
- Returns 5 colors: `[primary, secondary, accent, highlight, shadow]`
- Native decode target: maximum **256×256px** per side, `ARGB_8888`
- Palette quantization: MMCQ with up to 96 swatches and cleared filters
- Memory cache: LRU 256 entries
- Disk: debounced atomic JSON writes to
  `palette_cache_v<native-version>.json`
- Android native version is queried through `getCacheVersion`; non-Android/web
  uses the hardcoded fallback palette

## Assets Tree

```
assets/
├── fonts/
│   ├── sf_pro_text_black.otf
│   ├── sf_pro_text_bold.otf
│   ├── sf_pro_text_medium.otf
│   ├── sf_pro_text_regular.otf
│   └── sf_pro_text_semibold.otf
├── shaders/
│   └── fluid.frag
├── images/
│   └── search/
│       ├── akustik.webp
│       ├── pop.webp
│       ├── rock.webp
│       └── [other genre/artist .webp files]
└── play_store_512.png
```

Font family: **SF Pro Text** (Apple system font) — 5 weights.

## lib/utils/ Files

| File | Class/Symbol | Role |
|------|-------------|------|
| `constants.dart` | `kPageLeftPadding`, `kListLeftPadding`, `kCardMarginLeft` | Global layout constants for UI consistency |
| `safe_num.dart` | `SafeNumToInt` extension: `toIntOrElse` | NaN/Infinite safe int conversion |
| `sample_music_data.dart` | — | Barrel export: search categories, browse banners, radio stations |
| `zoom_fade_route.dart` | `ZoomFadeRoute` | `PageRouteBuilder` with pure fade transition |

No `lib/helpers/`, `lib/extensions/`, `lib/constants/`, `lib/config/`, `lib/controllers/` directories exist.

## lib/themes/ Structure

| File | Role |
|------|------|
| `theme_controller.dart` | `ThemeController` — all-static glass toggle manager |
| `glass_navbar.dart` | Glass nav bar `BackdropFilter` implementation |
