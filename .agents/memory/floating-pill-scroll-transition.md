---
name: Scroll-driven Floating Pill Transition
description: Shared scroll progress and geometry for the compact floating navbar/mini-player dock.
---

# Scroll-driven Floating Pill Transition

- `FloatingPillTransitionController.progress` is a shared 0–1 direct-manipulation signal. Each signed vertical scroll delta advances or reverses it over 72 logical pixels; it is clamped and does not update while the full player is expanded or while the mini-player is absent.
- `lib/bottom_nav_bar/bottom_nav/state.dart` listens at the active tab Navigator/Scaffold boundary, filters to root viewport notifications to avoid nested-scroll double counting, and returns false so page-level scroll observers keep working.
- `lib/themes/glass_navbar.dart` morphs the four-tab capsule into the selected destination icon. Search remains a separate circular action; the center slot is reserved for the mini-player.
- `lib/widgets/unified_morph_player.dart` uses the same progress to dock the mini-player into that slot and compress artwork/title/play controls. The existing player-sheet morph remains driven by `PlayerSheetController.progress`.
- Only the floating pill navbar style activates dock geometry; other navbar styles retain their existing layout.
- Regression tests: `test/services/floating_pill_transition_controller_test.dart`.
- Polish: docked left capsule, mini-player shell, and Search circle scale smoothly to 95%; artwork/title move right by up to 8 logical pixels via tested controller helpers.
- Device verification is still needed for gesture feel and glass `BackdropFilter` performance on the target Mi 9T.
