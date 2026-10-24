---
name: OpenCode background compaction
description: Background compaction is enabled project-wide via opencode.json experimental.background_compaction.
---

`opencode.json` enables OpenCode V2 background compaction:

```json
"experimental": { "background_compaction": true }
```

**Why:** long agent sessions in this repo hit the context limit; background
compaction writes the summary ahead of time (around 85% of the auto-compaction
threshold) so the session does not pause at the limit. It is an experimental
feature flag, so it can change or be removed without notice.

**How to apply:** keep the flag in the project `opencode.json` (not
`cli.json`, which is terminal-only). Config reloads live on save — no restart
needed. Related knobs stay in `compaction`: `auto` (default `true`),
`keep.tokens` (default 15000), `buffer` (default 15% of limit, min 16k).
Background compaction is skipped for sessions under ~64k tokens, right after a
model switch, for native provider compaction, and when a provider rejects a
request as too long; held summaries are in-memory only and are lost on restart.
