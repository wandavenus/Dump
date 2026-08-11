---
name: Notification artwork audit lessons
description: Durable rules for asynchronous notification and MediaSession artwork loading
---

# Notification artwork audit lessons

Async artwork completion must validate that its cache key still belongs to the current track before posting a notification; per-key generation alone does not prevent a cross-track stale notification. Session artwork caches shared by a handler and worker should be synchronized with in-flight request deduplication, and low-resolution URI fallbacks must never be enlarged.

**Why:** A previous-track worker can finish after a rapid skip and post its captured title/artwork over the current notification.

**How to apply:** Any notification artwork callback should check current identity at completion and rebuild from current state when needed. Caches shared between a main handler and worker executor must be synchronized or thread-confined, with in-flight deduplication. Negative artwork results should use a bounded TTL so MediaStore rescans can recover without restarting the process.