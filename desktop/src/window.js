// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { BrowserWindow, nativeTheme, screen } = require('electron');
const config = require('./config');
const store = require('./store');

const DEFAULT_SIZE = { width: 1280, height: 800 };
const MIN_SIZE = { width: 900, height: 600 };
const KEY = 'window';

const onWayland = process.platform === 'linux'
  && (process.env.XDG_SESSION_TYPE === 'wayland' || Boolean(process.env.WAYLAND_DISPLAY));

function canvasColor() {
  return nativeTheme.shouldUseDarkColors ? '#0F1410' : '#F8F6EE';
}

function overlap(a, b) {
  const width = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
  const height = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
  return { width: Math.max(0, width), height: Math.max(0, height) };
}

function titleBarVisible(bounds) {
  const bar = { x: bounds.x, y: bounds.y, width: bounds.width, height: 32 };
  return screen.getAllDisplays().some((display) => {
    const shared = overlap(bar, display.workArea);
    return shared.width >= Math.min(160, bounds.width) && shared.height >= 16;
  });
}

function restoredBounds() {
  const saved = store.get(KEY);
  const areas = screen.getAllDisplays().map((display) => display.workArea);
  const maxWidth = Math.max(...areas.map((area) => area.width), MIN_SIZE.width);
  const maxHeight = Math.max(...areas.map((area) => area.height), MIN_SIZE.height);
  const fit = (value, min, max, fallback) => (Number.isFinite(value) ? Math.round(Math.min(Math.max(value, min), max)) : fallback);
  const primary = screen.getPrimaryDisplay().workArea;
  const bounds = {
    width: fit(saved && saved.width, MIN_SIZE.width, maxWidth, Math.min(DEFAULT_SIZE.width, primary.width)),
    height: fit(saved && saved.height, MIN_SIZE.height, maxHeight, Math.min(DEFAULT_SIZE.height, primary.height)),
  };
  if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
    const placed = { ...bounds, x: Math.round(saved.x), y: Math.round(saved.y) };
    if (titleBarVisible(placed)) Object.assign(bounds, { x: placed.x, y: placed.y });
  }
  return { bounds, maximized: Boolean(saved && saved.maximized) };
}

function track(win) {
  let timer = null;
  const save = (now) => {
    clearTimeout(timer);
    timer = null;
    if (win.isDestroyed() || win.isFullScreen()) return;
    const normal = win.getNormalBounds();
    const value = { width: normal.width, height: normal.height, maximized: win.isMaximized() };
    if (!onWayland) Object.assign(value, { x: normal.x, y: normal.y });
    store.set(KEY, value, { now });
  };
  const later = () => {
    clearTimeout(timer);
    timer = setTimeout(() => save(false), 400);
  };
  for (const event of ['resize', 'move', 'maximize', 'unmaximize']) win.on(event, later);
  win.on('close', () => save(true));
  win.on('hide', () => save(true));
}

function createMainWindow() {
  const { bounds, maximized } = restoredBounds();
  const win = new BrowserWindow({
    ...bounds,
    minWidth: MIN_SIZE.width,
    minHeight: MIN_SIZE.height,
    title: config.brand.name,
    icon: config.resource(process.platform === 'win32' ? 'icon.ico' : 'icon.png'),
    backgroundColor: canvasColor(),
    show: false,
    autoHideMenuBar: true,
    webPreferences: {
      preload: config.preloadFile,
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
      webviewTag: false,
      navigateOnDragDrop: false,
      spellcheck: process.platform !== 'linux',
      devTools: config.isDev,
    },
  });
  win.on('page-title-updated', (event) => event.preventDefault());
  win.webContents.setVisualZoomLevelLimits(1, 1).catch(() => {});
  track(win);
  let shown = false;
  const show = () => {
    if (shown || win.isDestroyed()) return;
    shown = true;
    if (maximized) win.maximize();
    win.show();
  };
  win.once('ready-to-show', show);
  setTimeout(show, 3000);
  return win;
}

module.exports = { canvasColor, createMainWindow };
