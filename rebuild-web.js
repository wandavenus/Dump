#!/usr/bin/env node
/**
 * rebuild-web.js
 * Jalankan manual: node rebuild-web.js
 * Trigger flutter build web --release --base-href /
 */

const { spawn } = require('child_process');

const FLUTTER_BIN = '/home/runner/workspace/flutter-ws/flutter/bin/flutter';
const start = Date.now();
console.log('[rebuild] Memulai flutter build web...\n');

const proc = spawn(FLUTTER_BIN, ['build', 'web', '--release', '--base-href', '/', '--no-tree-shake-icons', '--no-wasm-dry-run'], {
  stdio: 'inherit',
  shell: false,
  env: { ...process.env, PATH: `/home/runner/workspace/flutter-ws/flutter/bin:${process.env.PATH}` },
});

proc.on('close', (code) => {
  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  if (code === 0) {
    console.log(`\n[rebuild] ✓ Selesai dalam ${elapsed}s — refresh browser untuk melihat perubahan`);
  } else {
    console.error(`\n[rebuild] ✗ Build gagal (exit ${code}) setelah ${elapsed}s`);
    process.exit(code);
  }
});
