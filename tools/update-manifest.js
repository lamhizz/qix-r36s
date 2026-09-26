#!/usr/bin/env node
/**
 * Automatically scans the `level-images/` directory and writes `level-images/manifest.json`.
 * Run with: node tools/update-manifest.js
 */

const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, '..', 'level-images');
const manifestPath = path.join(dir, 'manifest.json');

if (!fs.existsSync(dir)) {
  console.error('Directory does not exist:', dir);
  process.exit(1);
}

const files = fs.readdirSync(dir);
const images = files.filter(f => !f.startsWith('.') && /\.(jpe?g|png|webp)$/i.test(f));

fs.writeFileSync(manifestPath, JSON.stringify(images, null, 2) + '\n');
console.log(`[Manifest Generator] Wrote ${images.length} images to ${manifestPath}`);
images.forEach(img => console.log(' - ' + img));
