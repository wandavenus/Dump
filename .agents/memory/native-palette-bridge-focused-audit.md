---
name: NativePaletteBridge focused audit
description: Durable caveats found by a file-only review of the native palette bridge.
---

## Rule

Palette callbacks remain exactly-once even if the main Handler accepts but
never dispatches a runnable, and same-song requests remain coalesced until all
callbacks from a completed extraction are delivered.

**Why:** Handler enqueue success does not guarantee Looper delivery, while
removing the completed job before callback delivery permits duplicate extraction
work during a narrow lifecycle window.

**How to apply:** Preserve the bounded callback watchdog, cancel it after normal
delivery, and keep completed jobs only until their pending request IDs are
drained. Transient extraction failures must remain retryable and must not become
an unbounded result cache. See
`NativePaletteBridge_Focused_Audit_2026-08-05.md` for the full review.