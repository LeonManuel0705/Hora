// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { Notification, WebContentsView, app, ipcMain, session, shell } = require('electron');
const config = require('./config');
const copy = require('./copy');
const { log } = require('./log');
const { isNewerVersion, trustedUpdateUrl: trusted } = require('./rules');
const store = require('./store');

const FIRST_CHECK = 5000;
const INTERVAL = 2 * 60 * 60 * 1000;
const SKIPPED = 'skippedUpdate';
const RESIZE_EVENTS = ['resize', 'maximize', 'unmaximize', 'enter-full-screen', 'leave-full-screen'];

function platformKey() {
  return { win32: 'windows', linux: 'linux', darwin: 'macos' }[process.platform] || null;
}

function trustedUpdateUrl(value) {
  return trusted(value, config.brand);
}

function versionUrl() {
  return config.devSetting('HUB_DEV_UPDATE_URL') || `${config.brand.website}/version.json`;
}

async function fetchUpdate() {
  const response = await session.fromPartition('updates').fetch(versionUrl(), {
    signal: AbortSignal.timeout(5000),
    cache: 'no-store',
  });
  if (response.status !== 200) return null;
  const body = await response.text();
  if (body.length > 65536) return null;
  const data = JSON.parse(body);
  if (!data || typeof data.version !== 'string') return null;
  const version = data.version.trim();
  if (!isNewerVersion(version, app.getVersion())) return null;
  if (store.get(SKIPPED) === version) return null;
  const fallback = `${config.brand.website}/download`;
  const platformUrls = data.platformUrls && typeof data.platformUrls === 'object' ? data.platformUrls : {};
  const raw = [platformUrls[platformKey()], data.updateUrl].find((value) => typeof value === 'string') || fallback;
  const changelog = Array.isArray(data.changelog)
    ? data.changelog.map((line) => String(line).trim().slice(0, 300)).filter(Boolean)
    : [];
  return {
    version,
    versionName: typeof data.versionName === 'string' && data.versionName.trim() ? data.versionName.trim().slice(0, 80) : version,
    updateUrl: trustedUpdateUrl(raw) ? raw : fallback,
    changelog,
  };
}

function openUpdate(url) {
  if (!trustedUpdateUrl(url)) return;
  shell.openExternal(url).catch((error) => log('could not open the update page:', error.message));
}

class UpdateDialog {
  constructor(getWindow) {
    this.getWindow = getWindow;
    this.view = null;
    this.window = null;
    this.info = null;
    this.fit = () => {
      if (!this.view || !this.window || this.window.isDestroyed()) return;
      const { width, height } = this.window.getContentBounds();
      this.view.setBounds({ x: 0, y: 0, width, height });
    };

    ipcMain.handle('update:init', (event) => {
      if (!this.owns(event)) return null;
      return {
        title: copy.update.title,
        version: copy.update.version(this.info.versionName),
        newsTitle: copy.update.newsTitle,
        changelog: this.info.changelog.slice(0, 4),
        installed: copy.update.installed(app.getVersion()),
        labels: copy.update.labels,
      };
    });

    ipcMain.handle('update:choose', (event, choice) => {
      if (!this.owns(event)) return;
      const info = this.info;
      this.close();
      if (choice === 'download') openUpdate(info.updateUrl);
      else if (choice === 'skip') store.set(SKIPPED, info.version, { now: true });
    });
  }

  owns(event) {
    return Boolean(this.view) && event.sender === this.view.webContents && event.senderFrame === event.sender.mainFrame;
  }

  show(info) {
    const win = this.getWindow();
    if (!win || win.isDestroyed() || this.view) return;
    this.info = info;
    this.window = win;
    this.view = new WebContentsView({
      webPreferences: {
        preload: config.preloadFile,
        contextIsolation: true,
        sandbox: true,
        nodeIntegration: false,
        webSecurity: true,
        webviewTag: false,
        navigateOnDragDrop: false,
        spellcheck: false,
        devTools: config.isDev,
      },
    });
    this.view.setBackgroundColor('#00000000');
    win.contentView.addChildView(this.view);
    this.fit();
    for (const event of RESIZE_EVENTS) win.on(event, this.fit);
    const contents = this.view.webContents;
    contents.once('did-finish-load', () => contents.focus());
    contents.once('render-process-gone', () => this.close());
    contents.loadFile(config.updateFile).catch((error) => {
      log('update dialog failed to load:', error.message);
      this.close();
    });
  }

  close() {
    const { view, window: win } = this;
    if (!view) return;
    this.view = null;
    this.window = null;
    if (win && !win.isDestroyed()) {
      for (const event of RESIZE_EVENTS) win.off(event, this.fit);
      win.contentView.removeChildView(view);
      win.webContents.focus();
    }
    if (!view.webContents.isDestroyed()) view.webContents.close();
  }
}

const notified = new Set();
const liveNotifications = new Set();

function notify(info) {
  if (notified.has(info.version) || !Notification.isSupported()) return;
  notified.add(info.version);
  const text = copy.update.notification(info.versionName);
  const notification = new Notification({ title: text.title, body: text.body, icon: config.resource('icon.png') });
  liveNotifications.add(notification);
  notification.on('click', () => openUpdate(info.updateUrl));
  notification.on('close', () => liveNotifications.delete(notification));
  notification.show();
}

function scheduleUpdateChecks(getWindow) {
  const dialog = new UpdateDialog(getWindow);
  const check = async () => {
    try {
      const info = await fetchUpdate();
      if (!info) return;
      log(`update available: ${info.version}`);
      notify(info);
      dialog.show(info);
    } catch (error) {
      log('update check failed:', error.message);
    }
  };
  setTimeout(check, FIRST_CHECK);
  setInterval(check, INTERVAL);
}

module.exports = { scheduleUpdateChecks };
