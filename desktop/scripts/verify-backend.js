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
};
