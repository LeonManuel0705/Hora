// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { Menu, Tray, nativeImage, nativeTheme } = require('electron');
const { execFile } = require('child_process');
const config = require('./config');
const copy = require('./copy');
const { log } = require('./log');

function trayImage() {
  if (process.platform === 'win32') {
    const dark = nativeTheme.shouldUseDarkColorsForSystemIntegratedUI;
    return nativeImage.createFromPath(config.resource('tray', dark ? 'tray-dark.ico' : 'tray-light.ico'));
  }
  if (process.platform === 'darwin') {
    return nativeImage.createFromPath(config.resource('tray', nativeTheme.shouldUseDarkColors ? 'tray-dark.png' : 'tray-light.png'));
  }
  return nativeImage.createFromPath(config.resource('tray', 'tray-dark.png'));
}

function ask(file, args, pattern) {
  return new Promise((resolve) => {
    execFile(file, args, { timeout: 2000, encoding: 'utf8' }, (error, stdout) => {
      resolve(error ? null : pattern.test(stdout));
    });
  });
}

async function statusNotifierHost() {
  const viaDbusSend = await ask('dbus-send', [
    '--session', '--print-reply', '--dest=org.freedesktop.DBus', '/org/freedesktop/DBus',
    'org.freedesktop.DBus.NameHasOwner', 'string:org.kde.StatusNotifierWatcher',
  ], /boolean true/);
  if (viaDbusSend !== null) return viaDbusSend;
  return ask('gdbus', [
    'call', '--session', '--dest', 'org.freedesktop.DBus', '--object-path', '/org/freedesktop/DBus',
    '--method', 'org.freedesktop.DBus.NameHasOwner', 'org.kde.StatusNotifierWatcher',
  ], /true/);
}

async function trayIsVisible() {
  if (process.platform !== 'linux') return true;
  if (await statusNotifierHost()) return true;
  const desktops = (process.env.XDG_CURRENT_DESKTOP || '').toLowerCase().split(':');
  const gnome = desktops.some((desktop) => desktop === 'gnome' || desktop.startsWith('gnome-'));
  if (gnome) log('no status notifier host on GNOME, closing the window will quit');
  return !gnome;
}

function createTray({ onOpen, onNote, onQuit }) {
  let tray;
  try {
    tray = new Tray(trayImage());
  } catch (error) {
    log('tray unavailable:', error.message);
    return null;
  }
  tray.setToolTip(config.brand.name);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: copy.tray.open, click: onOpen },
    { label: copy.tray.note, click: onNote },
    { type: 'separator' },
    { label: copy.tray.quit, click: onQuit },
  ]));
  if (process.platform !== 'darwin') tray.on('click', onOpen);
  nativeTheme.on('updated', () => {
    if (!tray.isDestroyed()) tray.setImage(trayImage());
  });
  return tray;
}

module.exports = { createTray, trayIsVisible };
