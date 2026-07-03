---
name: Whole-body swipe-to-dismiss for modal sheets
description: Shared widget pattern for swipe-down-to-close across all bottom sheets, and which sheet type was excluded and why.
---

All `showModalBottomSheet` sheets in the app wrap their entire body (not just a
drag-handle header) in `lib/widgets/common/swipe_to_dismiss_sheet.dart`
(`SwipeToDismissSheet`), so users can swipe down anywhere on the sheet to
dismiss it, not just the top handle area.

**Why:** explicit user request — previously each sheet had its own local
`GestureDetector` + drag-offset state limited to the handle/header row only.

**How to apply:**
- New modal bottom sheets should wrap their root content in
  `SwipeToDismissSheet(child: ...)` instead of writing bespoke drag logic.
- `DraggableScrollableSheet`-based sheets (e.g. the settings log viewer, which
  has its own resize-drag + internal scrollable `ListView`) are intentionally
  **excluded** — whole-body vertical drag would conflict with its own
  scroll/resize gesture arena.
- Sheets with scrollable inner content (song info, sleep timer) accept the
  tradeoff that whole-body drag may compete with internal scroll in the
  gesture arena; this was an accepted tradeoff per user request, not a bug.
