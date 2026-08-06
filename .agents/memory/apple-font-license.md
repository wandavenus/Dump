---
name: Apple font redistribution constraint
description: SF Arabic from Apple Developer is restricted to Apple-platform mockups and cannot be embedded in Android APKs.
---

The Apple SF Arabic package must not be bundled into this Android Flutter app. Apple's license limits use to interface mockups for Apple operating systems, prohibits use for non-Apple operating systems, embedding, and unauthorized redistribution.

**Why:** The uploaded DMG contains the official SF Arabic package, but its license does not grant redistribution as an APK asset.

**How to apply:** Use an independently licensed Arabic font, such as a font under the SIL Open Font License, and retain its license/notice when adding it to Flutter assets.