import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { createCanvas, loadImage } from '/tmp/noisegraph-icon/node_modules/canvas/index.js';

const svgPath = process.argv[2];
const outDir = process.argv[3] || '.';
mkdirSync(outDir, { recursive: true });

const sizes = [48, 128, 512];
const svg = readFileSync(svgPath);

for (const size of sizes) {
  const img = await loadImage(`data:image/svg+xml;utf8,${svg.toString('utf8')}`);
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, size, size);
  const outPath = `${outDir}/noisegraph-${size}x${size}.png`;
  writeFileSync(outPath, canvas.toBuffer('image/png'));
  console.log(outPath);
}
