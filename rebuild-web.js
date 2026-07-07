#!/usr/bin/env node
/**
 * rebuild-web.js
 * Jalankan manual: node rebuild-web.js
 * Trigger flutter build web --release --base-href /
 */

const { spawn } = require('child_process');

const start = Date.now();
console.log('[rebuild] Memulai flutter build web...\n');

const proc = spawn('flutter', ['build', 'web', '--release', '--base-href', '/'], {
  stdio: 'inherit',
  shell: false,
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
