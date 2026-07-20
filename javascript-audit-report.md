# JavaScript Build Scripts Best-Practices Audit

Scope: All JavaScript build/rebuild/watch/server scripts under the repo root (`*.js` excluding `build/web/` compiled output).
Files audited:
- `watch-rebuild.js` (66 lines)
- `rebuild-web.js` (28 lines)
- `server.js` (73 lines)

---

## HIGH Severity

### 1. server.js:64 — Unhandled `fs.createReadStream` error event
**Best-practice violated:** Error handling — stream errors must be handled to prevent unhandled `error` events that crash the process or leave the response hanging.

```js
fs.createReadStream(fp).pipe(res);
```
If the file is deleted between the `stat` check and stream creation, or if a read error occurs, the stream emits an `error` event with no listener, terminating the Node.js process.

**Suggested fix:**
```js
const stream = fs.createReadStream(fp);
stream.on('error', (err) => {
  console.error(`[server] Read error for ${fp}:`, err);
  if (!res.headersSent) {
    res.writeHead(500);
    res.end('Internal Server Error');
  }
});
stream.pipe(res);
```

### 2. rebuild-web.js:20-28 — Missing `error` event handler on spawned child process
**Best-practice violated:** Resource/process hygiene — `spawn` can emit an `error` event (e.g., executable not found, ENOENT) before the `close` event. Without an `error` listener, the process silently fails to start and the parent never exits.

```js
const proc = spawn(FLUTTER_BIN, [...]);
proc.on('close', (code) => { ... });
```
If `FLUTTER_BIN` does not exist, `proc` emits `error` and no handler exists. The script hangs indefinitely.

**Suggested fix:**
```js
proc.on('error', (err) => {
  console.error(`[rebuild] Failed to start flutter: ${err.message}`);
  process.exit(1);
});
proc.on('close', (code) => { ... });
```

### 3. server.js:29 — Wildcard CORS (`Access-Control-Allow-Origin: *`)
**Best-practice violated:** Security — allowing any origin to read responses is overly permissive for a dev server and could expose the app to cross-origin attacks if used beyond local development.

```js
res.setHeader('Access-Control-Allow-Origin', '*');
```

**Suggested fix:**
Restrict to localhost or a configurable allowlist:
```js
const ALLOWED_ORIGINS = ['http://localhost:5000', 'http://127.0.0.1:5000'];
const origin = req.headers.origin;
if (ALLOWED_ORIGINS.includes(origin)) {
  res.setHeader('Access-Control-Allow-Origin', origin);
}
```

### 4. server.js:71 — Server binds to `0.0.0.0` without restriction
**Best-practice violated:** Security — binding to all network interfaces exposes the dev server to external access, which is dangerous if run in a CI environment, cloud VM, or shared network.

```js
server.listen(PORT, '0.0.0.0', () => {
```

**Suggested fix:**
Bind to `127.0.0.1` by default, with an opt-in env var:
```js
const HOST = process.env.HOST || '127.0.0.1';
server.listen(PORT, HOST, () => {
```

---

## MEDIUM Severity

### 5. watch-rebuild.js:29 — `exec` with shell command string
**Best-practice violated:** Security — `child_process.exec` executes via a shell (`/bin/sh`), interpreting shell metacharacters. While `BUILD_CMD` is currently hardcoded, the pattern is inherently riskier than `spawn` with an argv array.

```js
exec(BUILD_CMD, { env: { ...process.env, PATH: ... } }, callback);
```

**Suggested fix:**
Use `spawn` with an explicit argv array:
```js
const { spawn } = require('child_process');
const flutterProc = spawn(FLUTTER_BIN, ['build', 'web', '--release', '--base-href', '/', '--no-tree-shake-icons'], {
  env: { ...process.env, PATH: `/home/runner/flutter/bin:${process.env.PATH}` },
  stdio: 'inherit',
});
```

### 6. watch-rebuild.js:61-63 — Silent catch swallows `fs.watch` errors
**Best-practice violated:** Error handling — catching errors without logging or recovery hides filesystem issues (permission denied, ENOSPC, too many watchers).

```js
  } catch (e) {
    // target mungkin belum ada, skip saja
  }
```

**Suggested fix:**
```js
  } catch (e) {
    console.warn(`[watch] Cannot watch ${target}: ${e.message}`);
  }
```

### 7. server.js:44-66 — Callback pyramid (`tryFile` uses nested callbacks)
**Best-practice violated:** Async correctness / readability — `tryFile` nests `fs.stat` and `fs.createReadStream` callbacks, creating a callback pyramid. Modern Node.js provides `fs/promises` with `async`/`await`.

```js
  const tryFile = (fp) => {
    fs.stat(fp, (err, stat) => {
      if (!err && stat.isDirectory()) {
        tryFile(path.join(fp, 'index.html'));
        return;
      }
      if (err) {
        tryFile(path.join(BUILD_DIR, 'index.html'));
        return;
      }
      ...
      fs.createReadStream(fp).pipe(res);
    });
  };
```

**Suggested fix:**
```js
  const fsStat = fs.promises.stat;
  const fsCreateReadStream = fs.createReadStream;

  async function tryFile(fp) {
    try {
      const stat = await fsStat(fp);
      if (stat.isDirectory()) return tryFile(path.join(fp, 'index.html'));
    } catch {
      return tryFile(path.join(BUILD_DIR, 'index.html'));
    }
    const ext = path.extname(fp).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const basename = path.basename(fp);
    const cacheControl = NO_CACHE_FILES.includes(basename)
      ? 'no-cache, no-store, must-revalidate'
      : 'public, max-age=31536000, immutable';
    res.writeHead(200, { 'Content-Type': contentType, 'Cache-Control': cacheControl });
    const stream = fsCreateReadStream(fp);
    stream.on('error', (err) => { ... });
    stream.pipe(res);
  }
```

### 8. server.js:27 — `let` used for non-reassigned variable
**Best-practice violated:** Code quality — `urlPath` is never reassigned but is declared with `let`.

```js
  let urlPath = req.url.split('?')[0];
```

**Suggested fix:**
```js
  const urlPath = req.url.split('?')[0];
```

### 9. watch-rebuild.js, rebuild-web.js — No SIGINT/SIGTERM signal handling
**Best-practice violated:** Robustness — long-running scripts should handle SIGINT (Ctrl-C) and SIGTERM to clean up resources (child processes, file watchers) before exiting.

Neither script registers `process.on('SIGINT', ...)` or `process.on('SIGTERM', ...)`. If interrupted, spawned child processes and `fs.watch` watchers are left running.

**Suggested fix (watch-rebuild.js):**
```js
process.on('SIGINT', () => {
  console.log('\n[watch] Shutting down...');
  process.exit(0);
});
process.on('SIGTERM', () => process.exit(0));
```

**Suggested fix (rebuild-web.js):**
```js
proc.on('error', ...);
proc.on('close', ...);
process.on('SIGINT', () => {
  console.log('\n[rebuild] Interrupted, killing flutter process...');
  proc.kill('SIGTERM');
  process.exit(130);
});
```

### 10. watch-rebuild.js, rebuild-web.js — No unhandled rejection / uncaught exception handlers
**Best-practice violated:** Error handling — any unhandled promise rejection or uncaught exception will crash the process with an uninformative stack trace.

Neither script has:
```js
process.on('unhandledRejection', (reason) => { ... });
process.on('uncaughtException', (err) => { ... });
```

### 11. watch-rebuild.js:51-64 — `FSWatcher` objects discarded, no close/unwatch
**Best-practice violated:** Resource/process hygiene — `fs.watch()` returns `FSWatcher` instances with a `.close()` method. The return values are discarded, so there is no mechanism to stop watching or clean up on shutdown.

```js
WATCH_TARGETS.forEach(target => {
  watch(target, { recursive: true }, (event, filename) => { ... });
});
```

**Suggested fix:**
```js
const watchers = [];
WATCH_TARGETS.forEach(target => {
  try {
    const watcher = watch(target, { recursive: true }, handler);
    watchers.push(watcher);
  } catch (e) { ... }
});
process.on('SIGINT', () => {
  watchers.forEach(w => w.close());
  process.exit(0);
});
```

### 12. server.js:64 — No error handling on `createReadStream` (also covered in #1, but worth noting in context of pipe)
**Best-practice violated:** Error handling — `fs.createReadStream(fp).pipe(res)` without error handling on the stream. If the stream errors after piping starts and `res` headers are already sent, the response is left in an indeterminate state.

Combined with #1.

---

## LOW Severity

### 13. watch-rebuild.js:12, rebuild-web.js:10 — Hardcoded Flutter binary path
**Best-practice violated:** Code quality / portability — `/home/runner/flutter/bin/flutter` assumes a specific CI environment. The script will not work on any other machine without modification.

```js
const FLUTTER_BIN = '/home/runner/flutter/bin/flutter';
```

**Suggested fix:**
```js
const FLUTTER_BIN = process.env.FLUTTER_BIN || 'flutter';
```

### 14. watch-rebuild.js:13 — Hardcoded build flags as a shell command string
**Best-practice violated:** Code quality — `--release --base-href / --no-tree-shake-icons` is baked into a command string rather than parameterized.

**Suggested fix:**
Define flags as an array and use `spawn` (see #5).

### 15. server.js:5 — Hardcoded PORT
**Best-practice violated:** Code quality — port `5000` is hardcoded with no `process.env.PORT` fallback.

```js
const PORT = 5000;
```

**Suggested fix:**
```js
const PORT = parseInt(process.env.PORT, 10) || 5000;
```

### 16. server.js:6 — Hardcoded `BUILD_DIR`
**Best-practice violated:** Code quality — the build output directory is hardcoded relative to `__dirname`. While this is acceptable for a project-specific script, it reduces reusability.

### 17. server.js:42 — Hardcoded `NO_CACHE_FILES` list
**Best-practice violated:** Maintainability — the no-cache list is hardcoded. If Flutter changes its service worker or bootstrap filenames, this list silently goes stale.

### 18. server.js:8-24 — Hardcoded `MIME_TYPES` map
**Best-practice violated:** Modularity / maintainability — a full MIME type map is duplicated rather than using a well-maintained library like `mime-types` or `media-typer`. The map is also incomplete (e.g., missing `.webp`, `.avif`, `.js.map`).

### 19. server.js:27 — No input validation on `urlPath`
**Best-practice violated:** Security / robustness — `req.url.split('?')[0]` is not validated for null bytes, excessive length, or malformed sequences before being passed to `path.join`.

**Suggested fix:**
```js
const rawPath = req.url.split('?')[0];
const urlPath = rawPath.replace(/\0/g, '').slice(0, 4096);
```

### 20. server.js:64 — Missing `Content-Length` header
**Best-practice violated:** HTTP best practices — responses do not include `Content-Length`, making it harder for clients to track download progress or handle connection resumption.

---

## Summary Table

| # | File:Line | Severity | Issue |
|---|-----------|----------|-------|
| 1 | server.js:64 | HIGH | Unhandled `createReadStream` error event |
| 2 | rebuild-web.js:20-28 | HIGH | Missing `error` event on `spawn` result |
| 3 | server.js:29 | HIGH | Wildcard CORS (`*`) |
| 4 | server.js:71 | HIGH | Bind to `0.0.0.0` without restriction |
| 5 | watch-rebuild.js:29 | MEDIUM | `exec` with shell command string |
| 6 | watch-rebuild.js:61-63 | MEDIUM | Silent catch swallows watch errors |
| 7 | server.js:44-66 | MEDIUM | Callback pyramid in `tryFile` |
| 8 | server.js:27 | MEDIUM | `let` for non-reassigned variable |
| 9 | watch-rebuild.js, rebuild-web.js | MEDIUM | No SIGINT/SIGTERM handling |
| 10 | watch-rebuild.js, rebuild-web.js | MEDIUM | No unhandled rejection handlers |
| 11 | watch-rebuild.js:51-64 | MEDIUM | FSWatcher objects discarded |
| 12 | server.js:64 | MEDIUM | No stream error handling in pipe |
| 13 | watch-rebuild.js:12, rebuild-web.js:10 | LOW | Hardcoded Flutter binary path |
| 14 | watch-rebuild.js:13 | LOW | Hardcoded build flags |
| 15 | server.js:5 | LOW | Hardcoded PORT |
| 16 | server.js:6 | LOW | Hardcoded BUILD_DIR |
| 17 | server.js:42 | LOW | Hardcoded NO_CACHE_FILES |
| 18 | server.js:8-24 | LOW | Hardcoded MIME_TYPES map |
| 19 | server.js:27 | LOW | No URL path validation |
| 20 | server.js:64 | LOW | Missing Content-Length header |
