---
name: Apple font redistribution constraint
description: SF Arabic from Apple Developer is restricted to Apple-platform mockups and cannot be embedded in Android APKs.
---

The Apple SF Arabic package must not be bundled into this Android Flutter app. Apple's license limits use to interface mockups for Apple operating systems, prohibits use for non-Apple operating systems, embedding, and unauthorized redistribution.

**Why:** The uploaded DMG contains the official SF Arabic package, but its license does not grant redistribution as an APK asset.

**How to apply:** Use an independently licensed Arabic font, such as a font under the SIL Open Font License, and retain its license/notice when adding it to Flutter assets.

The selected replacement is Noto Sans Arabic from Google Fonts, distributed under SIL OFL 1.1. Keep its OFL notice beside the bundled font asset.

**Why:** The app needs a bundled Arabic fallback for Android, and Noto Sans Arabic covers the Arabic Unicode ranges without relying on device-specific fallback fonts.

**How to apply:** Keep SF Pro Text as the primary lyric font and use Noto Sans Arabic through `fontFamilyFallback` in both normal lyric Text widgets and custom karaoke TextPainters.