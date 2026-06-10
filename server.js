const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5000;
const BUILD_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.wasm': 'application/wasm',
};

const server = http.createServer((req, res) => {
  let urlPath = req.url.split('?')[0];

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');

  let filePath = path.join(BUILD_DIR, urlPath);

  if (!filePath.startsWith(BUILD_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

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
      const ext = path.extname(fp).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': contentType });
      fs.createReadStream(fp).pipe(res);
    });
  };

  tryFile(filePath);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Music Player running at http://0.0.0.0:${PORT}`);
});
