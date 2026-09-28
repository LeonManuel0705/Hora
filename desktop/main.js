// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app, Menu, Notification, globalShortcut, ipcMain, nativeTheme, session, shell } = require('electron');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const config = require('./src/config');
const copy = require('./src/copy');
const { log, openLogs, backendLogFile, logDirectory } = require('./src/log');
const { chooseUserData } = require('./src/profile');
const store = require('./src/store');
const { Backend } = require('./src/backend');
const { hardenContents, hardenSession, isHubUrl, openExternally } = require('./src/security');
const { canvasColor, createMainWindow } = require('./src/window');
const { createScreens } = require('./src/screens');
const { createTray, trayIsVisible } = require('./src/tray');
const { scheduleUpdateChecks } = require('./src/updates');

const THEME_SOURCES = new Set(['system', 'light', 'dark']);
const QUICK_NOTE_SHORTCUT = 'CommandOrControl+Shift+N';

const token = crypto.randomBytes(32).toString('hex');

let mainWindow = null;
let backend = null;
let screens = null;
let tray = null;
let backgroundMode = true;
let showingHub = false;
let generation = 0;
let retrying = false;
let quitting = false;
let readyToQuit = false;
const recoveries = [];
const liveNotifications = new Set();
const quickNote = { pending: false, navigated: false, timer: null };

function liveWindow() {
  return mainWindow && !mainWindow.isDestroyed() ? mainWindow : null;
}

function showWindow() {
  const win = liveWindow();
  if (!win) return;
  if (win.isMinimized()) win.restore();
  if (!win.isVisible()) win.show();
  win.focus();
}

function announceBackground() {
  if (store.get('backgroundHintShown') || !Notification.isSupported()) return;
  store.set('backgroundHintShown', true, { now: true });
  const hint = copy.backgroundHint(process.platform);
  const notification = new Notification({ title: hint.title, body: hint.body, icon: config.resource('icon.png') });
  liveNotifications.add(notification);
  notification.on('click', () => {
    liveNotifications.delete(notification);
    showWindow();
  });
  notification.on('close', () => liveNotifications.delete(notification));
  notification.show();
}

async function clearWebData(ses) {
  try {
    await ses.clearCache();
    await ses.clearStorageData();
  } catch (error) {
    log('could not clear web data:', error.message);
  }
}

async function clearOfflineData(ses) {
  try {
    await ses.clearStorageData({ storages: ['serviceworkers', 'cachestorage'] });
  } catch (error) {
    log('could not clear the offline cache:', error.message);
  }
}

function loadHub(url = config.hubUrl) {
  const win = liveWindow();
  if (!win || !backend || !backend.ready) return;
  showingHub = true;
  screens.detach();
  win.loadURL(url, { extraHeaders: `X-Hub-Token: ${token}\n` }).catch((error) => {
    if (error.code !== 'ERR_ABORTED') log('hub failed to load:', error.message);
  });
}

function openHubUrl(url) {
  if (showingHub) loadHub(url);
}

async function startBackend() {
  const current = ++generation;
  showingHub = false;
  screens.loading(copy.progress.starting);
  const result = await backend.start((stage) => {
    if (current === generation && !quitting && copy.progress[stage]) screens.loading(copy.progress[stage]);
  });
  if (current !== generation || quitting) return;
  if (!result.ok) {
    screens.problem(result.problem.kind, result.problem);
    return;
  }
  loadHub();
}

async function retry() {
  if (retrying || quitting) return;
  retrying = true;
  try {
    generation += 1;
    showingHub = false;
    screens.loading(copy.progress.starting);
    await backend.stop();
    await clearOfflineData(session.defaultSession);
  } finally {
    retrying = false;
  }
  if (!quitting) await startBackend();
}

function openLog() {
  const file = backendLogFile();
  const target = file && fs.existsSync(file) ? file : logDirectory();
  if (!target) return;
  shell.openPath(target).then((problem) => {
    if (problem) log('could not open the log:', problem);
  });
}

function onScreenAction(action) {
  if (action === 'retry') retry();
  else if (action === 'log') openLog();
  else if (action === 'link') openExternally('https://www.python.org/downloads/');
}

function hubIsLoaded() {
  const win = liveWindow();
  return Boolean(win) && showingHub && isHubUrl(win.webContents.getURL());
}

function deliverQuickNote() {
  if (!quickNote.pending || !hubIsLoaded()) return;
  const win = liveWindow();
  win.webContents.focus();
  win.webContents.send('hub:quick-note');
}

function requestQuickNote() {
  showWindow();
  quickNote.pending = true;
  quickNote.navigated = false;
  clearTimeout(quickNote.timer);
  quickNote.timer = setTimeout(() => {
    quickNote.pending = false;
  }, 120000);
  const win = liveWindow();
  if (win && !win.webContents.isLoading()) deliverQuickNote();
}

function fromHub(event) {
  const win = liveWindow();
  return Boolean(win)
    && event.sender === win.webContents
    && event.senderFrame === win.webContents.mainFrame
    && isHubUrl(event.senderFrame.url);
}

function registerHubBridge() {
  ipcMain.on('hub:theme', (event, source) => {
    if (!fromHub(event) || !THEME_SOURCES.has(source)) return;
    if (nativeTheme.themeSource !== source) nativeTheme.themeSource = source;
    store.set('themeSource', source);
  });

  ipcMain.on('hub:notification-click', (event) => {
    if (fromHub(event)) showWindow();
  });

  ipcMain.on('hub:quick-note-result', (event, result) => {
    if (!fromHub(event) || !quickNote.pending) return;
    if (result === 'opened') {
      quickNote.pending = false;
      clearTimeout(quickNote.timer);
    } else if (result === 'missing' && !quickNote.navigated) {
      quickNote.navigated = true;
      loadHub();
    } else {
      quickNote.pending = false;
    }
  });
}

function recover() {
  const now = Date.now();
  while (recoveries.length && now - recoveries[0] > 60000) recoveries.shift();
  recoveries.push(now);
  if (recoveries.length > 3) {
    log('the page keeps crashing, giving up for now');
    return;
  }
  if (showingHub && backend.ready) loadHub();
  else screens.reload();
}

function wireWindow(win) {
  win.on('close', (event) => {
    if (quitting || !backgroundMode) return;
    event.preventDefault();
    win.hide();
    announceBackground();
  });
  win.on('closed', () => {
    mainWindow = null;
  });

  win.webContents.on('did-finish-load', () => {
    if (showingHub && isHubUrl(win.webContents.getURL())) deliverQuickNote();
  });

  win.webContents.on('did-fail-load', (_event, code, description, url, isMainFrame) => {
    if (!isMainFrame || code === -3 || quitting || !showingHub || !isHubUrl(url)) return;
    log(`hub page failed: ${code} ${description}`);
    if (!backend.running) return;
    showingHub = false;
    screens.problem('page', { description: `${description} (${code})` });
  });

  win.webContents.on('render-process-gone', (_event, details) => {
    log('page renderer gone:', details.reason, details.exitCode);
    if (quitting || details.reason === 'clean-exit') return;
    recover();
  });

  nativeTheme.on('updated', () => {
    const current = liveWindow();
    if (current) current.setBackgroundColor(canvasColor());
  });
}

function registerShortcut() {
  try {
    const registered = globalShortcut.register(QUICK_NOTE_SHORTCUT, requestQuickNote);
    log(registered ? 'quick note shortcut registered' : 'quick note shortcut is taken by another app');
  } catch (error) {
    log('quick note shortcut failed:', error.message);
  }
}

async function setUpTray() {
  tray = createTray({ onOpen: showWindow, onNote: requestQuickNote, onQuit: () => app.quit() });
  if (!tray) {
    backgroundMode = process.platform === 'darwin';
    return;
  }
  backgroundMode = process.platform === 'darwin' || (await trayIsVisible());
}

async function ready() {
  if (process.platform !== 'darwin') Menu.setApplicationMenu(null);
  const ses = session.defaultSession;
  hardenSession(ses);
  const cleared = clearWebData(ses);

  backend = new Backend({ token, dataDir: path.join(app.getPath('userData'), 'data') });
  backend.on('crashed', (exit) => {
    if (quitting) return;
    generation += 1;
    showingHub = false;
    screens.problem('crashed', exit);
  });

  screens = createScreens({ getWindow: liveWindow, onAction: onScreenAction });
  registerHubBridge();

  mainWindow = createMainWindow();
  wireWindow(mainWindow);
  screens.loading(copy.progress.starting);

  setUpTray().catch((error) => log('tray setup failed:', error.message));
  registerShortcut();

  await cleared;
  startBackend();
  scheduleUpdateChecks(liveWindow);
}

function beforeQuit(event) {
  quitting = true;
  store.flush();
  if (readyToQuit || !backend) return;
  const stopped = backend.close();
  if (!backend.running) return;
  event.preventDefault();
  stopped
    .catch((error) => log('backend did not stop cleanly:', error.message))
    .finally(() => {
      readyToQuit = true;
      app.quit();
    });
}

function boot() {
  openLogs(path.join(app.getPath('userData'), 'logs'));
  store.load(app.getPath('userData'));
  log(`starting ${config.brand.name} ${app.getVersion()} (Electron ${process.versions.electron}, ${process.platform} ${process.arch})`);

  const source = store.get('themeSource');
  if (THEME_SOURCES.has(source)) nativeTheme.themeSource = source;

  if (process.platform === 'win32') {
    app.setAppUserModelId(config.appId);
    app.disableHardwareAcceleration();
  }

  app.on('second-instance', showWindow);
  app.on('activate', showWindow);
  app.on('before-quit', beforeQuit);
  app.on('will-quit', () => {
    globalShortcut.unregisterAll();
    store.flush();
  });
  app.on('window-all-closed', () => app.quit());
  app.on('session-end', () => backend && backend.stopNow());
  app.on('web-contents-created', (_event, contents) => hardenContents(contents, { openHubUrl }));
  process.on('exit', () => backend && backend.stopNow());
  process.on('uncaughtException', (error) => log('uncaught exception:', error));
  process.on('unhandledRejection', (error) => log('unhandled rejection:', error));

  app.whenReady().then(ready).catch((error) => log('startup failed:', error));
}

app.setName(config.brand.name);
chooseUserData();

if (app.requestSingleInstanceLock()) boot();
else app.quit();
