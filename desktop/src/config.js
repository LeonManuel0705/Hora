// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app } = require('electron');
const path = require('path');
const brand = require('../brand.json');

const isDev = !app.isPackaged;
const appDir = path.resolve(__dirname, '..');

function devSetting(name) {
  if (!isDev) return null;
  const value = process.env[name];
  return value ? value : null;
}

function devPort() {
  const value = Number(devSetting('HUB_DEV_PORT'));
  return Number.isInteger(value) && value >= 1024 && value <= 65535 ? value : null;
}

const port = devPort() || 5050;
const hubOrigin = `http://127.0.0.1:${port}`;

module.exports = {
  brand,
  isDev,
  devSetting,
  port,
  hubOrigin,
  hubUrl: `${hubOrigin}/hub`,
  appId: `app.${brand.name.toLowerCase()}.desktop`,
  appDir,
  preloadFile: path.join(appDir, 'src', 'preload.js'),
  screenFile: path.join(appDir, 'screens', 'shell.html'),
  updateFile: path.join(appDir, 'screens', 'update.html'),
  resource: (...parts) => path.join(appDir, 'resources', ...parts),
};
