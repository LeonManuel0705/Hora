// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const source = path.join(repoRoot, 'dist', 'server');
const target = path.resolve(__dirname, '..', 'frozen-backend', 'server');
const executable = process.platform === 'win32' ? 'server.exe' : 'server';

if (!fs.existsSync(path.join(source, executable))) {
  console.error(`bundle-backend: ${path.join(source, executable)} is missing. Run scripts/build_backend.sh first.`);
  process.exit(1);
}

fs.rmSync(target, { recursive: true, force: true });
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.cpSync(source, target, { recursive: true });
console.log(`bundle-backend: copied ${source} to ${target}`);
