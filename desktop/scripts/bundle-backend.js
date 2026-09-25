// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

// Copy the PyInstaller-frozen backend (../dist/server, produced by
// scripts/build_backend.sh) into frozen-backend/server so electron-builder
// bundles it as extraResources. Cross-platform (uses fs.cpSync). Run before
// `electron-builder`. No-op with a clear message if the freeze hasn't been built.
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const src = path.join(repoRoot, 'dist', 'server');
const destParent = path.resolve(__dirname, '..', 'frozen-backend');
const dest = path.join(destParent, 'server');

if (!fs.existsSync(path.join(src, process.platform === 'win32' ? 'server.exe' : 'server'))) {
  console.warn(
    `bundle-backend: no frozen backend at ${src}.\n` +
    `Run scripts/build_backend.sh first to ship a Python-free build; ` +
    `otherwise the app falls back to requiring a system Python.`
  );
  process.exit(0);
}

fs.rmSync(dest, { recursive: true, force: true });
fs.mkdirSync(destParent, { recursive: true });
fs.cpSync(src, dest, { recursive: true });
console.log(`bundle-backend: copied ${src} -> ${dest}`);
