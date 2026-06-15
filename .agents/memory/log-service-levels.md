---
name: LogService levels
description: LogService rewritten with 5 levels, LogEntry model, and improved log viewer.
---

# LogService — 5-Level Architecture

**Rule:** LogService sekarang punya 5 level. Gunakan level yang tepat untuk noise control.

| Level | Method | Use |
|-------|--------|-----|
| verbose | `LogService.verbose()` | Hot paths, position ticks, render calls |
| debug | `LogService.debug()` | State changes, transitions |
| info | `LogService.log()` | Normal operation milestones |
| warning | `LogService.warn()` | Recoverable errors, fallbacks |
| error | `LogService.error()` | Exceptions, stack traces |

## LogEntry fields
- `timestamp` (DateTime) — with milliseconds
- `category` (String) — e.g. 'AudioService', 'Crossfade'
- `message` (String)
- `level` (LogLevel)
- `extra` (Map<String, dynamic>?) — optional structured data
- `elapsed` (Duration?) — optional perf timing
- `stackTrace` (StackTrace?) — for errors

## Log Viewer
- Filter by category (chip row)
- Color-coded per level (grey/blue/green/orange/red)
- Copy button → Clipboard.setData → needs `import 'package:flutter/services.dart'` in settings_page.dart barrel
- 500 entry FIFO max

**Why:** Uniform `LogService.log()` made it impossible to filter debug noise from real errors.

**How to apply:** New code → choose level based on frequency and importance. Never add verbose inside setState/build unless behind a `kDebugMode` guard.
