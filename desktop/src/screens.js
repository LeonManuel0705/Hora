// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { ipcMain } = require('electron');
const { pathToFileURL } = require('url');
const config = require('./config');
const copy = require('./copy');
const { log } = require('./log');

const screenPath = pathToFileURL(config.screenFile).pathname;

function isScreenUrl(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'file:') return false;
    return process.platform === 'win32'
      ? decodeURIComponent(parsed.pathname).toLowerCase() === decodeURIComponent(screenPath).toLowerCase()
      : parsed.pathname === screenPath;
  } catch {
    return false;
  }
}

function createScreens({ getWindow, onAction }) {
  let state = null;
  let mounted = false;
  let listening = false;

  function fromScreen(event) {
    const win = getWindow();
    return Boolean(win)
      && !win.isDestroyed()
      && event.sender === win.webContents
      && event.senderFrame === win.webContents.mainFrame
      && isScreenUrl(event.senderFrame.url);
  }

  function present(next) {
    state = { name: config.brand.name, ...next };
    const win = getWindow();
    if (!win || win.isDestroyed()) return;
    if (mounted) {
      if (listening) win.webContents.send('screen:state', state);
      return;
    }
    mounted = true;
    listening = false;
    win.loadFile(config.screenFile).catch((error) => {
      if (error.code !== 'ERR_ABORTED') log('screen failed to load:', error.message);
    });
  }

  ipcMain.handle('screen:init', (event) => {
    if (!fromScreen(event)) return null;
    listening = true;
    return state;
  });

  ipcMain.handle('screen:action', (event, action) => {
    if (!fromScreen(event) || !state || !state.actions || !state.actions[action]) return false;
    onAction(action, state);
    return true;
  });

  return {
    loading(status) {
      present({ view: 'loading', status });
    },
    problem(kind, info) {
      present({ view: 'problem', kind, ...copy.problem(kind, info) });
    },
    detach() {
      mounted = false;
      listening = false;
    },
    reload() {
      mounted = false;
      listening = false;
      if (state) present(state);
    },
  };
}

module.exports = { createScreens };
