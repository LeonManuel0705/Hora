// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const fs = require('fs');
const path = require('path');

exports.default = async function verifyBackend(context) {
  const platform = context.electronPlatformName;
  const executable = platform === 'win32' ? 'server.exe' : 'server';
  const resources = platform === 'darwin'
    ? path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`, 'Contents', 'Resources')
    : path.join(context.appOutDir, 'resources');
  const server = path.join(resources, 'backend', 'server', executable);
  if (!fs.existsSync(server)) {
    throw new Error(`The frozen backend is missing at ${server}. Run scripts/build_backend.sh and npm run bundle-backend on the target platform first.`);
  }
  const head = Buffer.alloc(4);
  const handle = fs.openSync(server, 'r');
  try {
    fs.readSync(handle, head, 0, 4, 0);
  } finally {
    fs.closeSync(handle);
  }
  const expected = { win32: [0x4d, 0x5a], linux: [0x7f, 0x45, 0x4c, 0x46] }[platform];
  if (expected && !expected.every((byte, index) => head[index] === byte)) {
    throw new Error(`The frozen backend at ${server} was not built for ${platform}. Freeze it on the target platform.`);
  }
  if (platform === 'linux' && !(fs.statSync(server).mode & 0o111)) {
    throw new Error(`The frozen backend at ${server} is not executable.`);
  }
};
