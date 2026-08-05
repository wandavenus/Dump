---
name: NativePaletteBridge focused audit
description: Durable caveats found by a file-only review of the native palette bridge.
---

## Rule

The bridge's exactly-once callback logic still depends on lifecycle disposal if
the main Handler accepts a runnable and the Looper stops dispatching it.
Coalescing also ends when extraction completes, before callback delivery finishes,
so a narrow duplicate-work window remains.

**Why:** `Handler.post()` returning `true` confirms enqueueing, not eventual
execution, and the per-song in-flight entry is removed before result runnables
are posted.

**How to apply:** Any future lifecycle hardening should preserve exactly-once
MethodChannel completion and any coalescing fix should remain bounded and keep
transient failures retryable. See
`NativePaletteBridge_Focused_Audit_2026-08-05.md` for the full review.