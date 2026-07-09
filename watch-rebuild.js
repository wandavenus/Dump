#!/usr/bin/env node
/**
 * watch-rebuild.js
 * Watches lib/, assets/, and pubspec.yaml for changes,
 * then triggers `flutter build web --release --base-href /` automatically.
 */

const { watch } = require('fs');
const { exec } = require('child_process');

const WATCH_TARGETS = ['lib', 'assets', 'pubspec.yaml'];
const FLUTTER_BIN = '/home/runner/flutter/bin/flutter';
const BUILD_CMD = `"${FLUTTER_BIN}" build web --release --base-href / --no-tree-shake-icons`;
const DEBOUNCE_MS = 1500; // wait 1.5s after last change before building

let buildTimer = null;
let building = false;
let pendingAfterBuild = false;

function runBuild() {
  if (building) {
    pendingAfterBuild = true;
    return;
  }
  building = true;
  pendingAfterBuild = false;
  const start = Date.now();
  console.log(`\n[watch] Perubahan terdeteksi — memulai rebuild web...`);
  exec(BUILD_CMD, { env: { ...process.env, PATH: `/home/runner/flutter/bin:${process.env.PATH}` } }, (err, stdout, stderr) => {
    building = false;
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    if (err) {
      console.error(`[watch] Build GAGAL (${elapsed}s):`);
      console.error(stderr || err.message);
    } else {
      console.log(`[watch] Build selesai dalam ${elapsed}s — refresh browser untuk melihat perubahan`);
    }
    if (pendingAfterBuild) {
      scheduleRebuild();
    }
  });
}

function scheduleRebuild() {
  if (buildTimer) clearTimeout(buildTimer);
  buildTimer = setTimeout(runBuild, DEBOUNCE_MS);
}

const WATCH_EXTS = new Set(['.dart', '.yaml', '.json', '.png', '.jpg', '.svg', '.ttf', '.otf', '.woff', '.woff2']);

WATCH_TARGETS.forEach(target => {
  try {
    watch(target, { recursive: true }, (event, filename) => {
      if (!filename) return;
      const ext = require('path').extname(filename).toLowerCase();
      if (!WATCH_EXTS.has(ext)) return;
      console.log(`[watch] ${event}: ${target}/${filename}`);
      scheduleRebuild();
    });
    console.log(`[watch] Memantau: ${target}/`);
  } catch (e) {
    // target mungkin belum ada, skip saja
  }
});

console.log('[watch] Siap — edit file Dart/YAML untuk otomatis trigger rebuild web.\n');
