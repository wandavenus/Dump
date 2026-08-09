# MediaStore Reconcile Retry Fix

## Problem
When `MediaStoreService` has no in-memory song cache, `getSongs()` calls `refreshSongs()` directly. A failed native refresh records `_lastFailedReconcile`, but that timestamp is only consulted by the cached/background-reconcile path. Repeated callers during the failure window can therefore start another native query immediately after the previous failure.

## Design
Keep explicit `refreshSongs()` behavior unchanged so callers requesting a refresh can retry immediately. Apply the existing 10-second cooldown only to the automatic/background reconcile path, including the cold-start/no-cache path.

For a cold start without cache, `getSongs()` checks `_lastFailedReconcile` before invoking `refreshSongs()`. If the previous refresh failed within the cooldown window, it returns an empty list rather than starting another native query. After the cooldown expires, a new refresh is allowed.

## Constraints
- Do not change the native MediaStore query.
- Do not change the 20-second native query timeout.
- Do not change cache persistence or in-flight deduplication.
- Do not block explicit/manual `refreshSongs()` calls with the automatic cooldown.
- Preserve existing success behavior.

## Verification
After implementation, inspect the resulting file and verify repository CI/status where available.
