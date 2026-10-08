---
name: Notification artwork audit lessons
description: Durable rules for asynchronous notification and MediaSession artwork loading
---

# Notification artwork audit lessons

Async artwork completion must validate that its cache key still belongs to the current track before posting a notification; per-key generation alone does not prevent a cross-track stale notification. Shared artwork caches need process-wide synchronization/in-flight deduplication, and low-resolution URI fallbacks must never be enlarged. See `Notification_Artwork_Audit_2026-08-11.md` for the latest audit.

**Why:** A previous-track worker can finish after a rapid skip and post its captured title/artwork over the current notification.

**How to apply:** Any notification artwork callback should check current identity at completion and rebuild from current state when needed. Caches shared between Activity/service instances must use a process-wide lock or single owner; handler/worker access needs in-flight deduplication. Negative artwork results should use a bounded TTL so MediaStore rescans can recover without restarting the process.