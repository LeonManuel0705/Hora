// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { contextBridge, ipcRenderer } = require('electron');

const NOTIFICATION_CLICK = 'app-shell-notification-click';

function currentPage() {
  if (location.protocol === 'file:') {
    if (location.pathname.endsWith('/screens/shell.html')) return 'screen';
    if (location.pathname.endsWith('/screens/update.html')) return 'update';
    return null;
  }
  if (location.protocol === 'http:' && location.hostname === '127.0.0.1') return 'hub';
  return null;
}

function exposeScreen() {
  contextBridge.exposeInMainWorld('shellScreen', {
    init: () => ipcRenderer.invoke('screen:init'),
    act: (action) => ipcRenderer.invoke('screen:action', String(action)),
    onState: (listener) => {
      ipcRenderer.removeAllListeners('screen:state');
      ipcRenderer.on('screen:state', (_event, state) => listener(state));
    },
  });
}

function exposeUpdate() {
  contextBridge.exposeInMainWorld('shellUpdate', {
    init: () => ipcRenderer.invoke('update:init'),
    choose: (choice) => ipcRenderer.invoke('update:choose', String(choice)),
  });
}

function installNotificationHook(eventName) {
  const Native = window.Notification;
  if (typeof Native !== 'function') return;
  const signal = () => document.dispatchEvent(new CustomEvent(eventName));
  const Wrapped = new Proxy(Native, {
    construct(target, args, newTarget) {
      const notification = Reflect.construct(target, args, newTarget === Wrapped ? target : newTarget);
      notification.addEventListener('click', signal);
      return notification;
    },
  });
  window.Notification = Wrapped;
}

function themeSource() {
  const root = document.documentElement;
  if (!root) return null;
  const mode = root.dataset.themeMode;
  if (mode === 'light' || mode === 'dark') return mode;
  if (mode === 'auto' || mode === 'system') return 'system';
  try {
    if (localStorage.getItem('app-theme-mode') === 'system') return 'system';
  } catch {}
  const theme = root.dataset.theme;
  return theme === 'light' || theme === 'dark' ? theme : 'system';
}

function watchTheme() {
  let reported = null;
  const report = () => {
    const source = themeSource();
    if (!source || source === reported) return;
    reported = source;
    ipcRenderer.send('hub:theme', source);
  };
  const start = () => {
    report();
    new MutationObserver(report).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme', 'data-theme-mode'],
    });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
}

function answerQuickNote() {
  ipcRenderer.on('hub:quick-note', () => {
    if (!document.getElementById('noteSheet') || !document.body) {
      ipcRenderer.send('hub:quick-note-result', 'missing');
      return;
    }
    document.body.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'N',
      code: 'KeyN',
      ctrlKey: true,
      shiftKey: true,
      bubbles: true,
      cancelable: true,
    }));
    ipcRenderer.send('hub:quick-note-result', 'opened');
  });
}

function prepareHub() {
  if (typeof contextBridge.executeInMainWorld === 'function') {
    try {
      contextBridge.executeInMainWorld({ func: installNotificationHook, args: [NOTIFICATION_CLICK] });
    } catch {}
  }
  document.addEventListener(NOTIFICATION_CLICK, () => ipcRenderer.send('hub:notification-click'));
  watchTheme();
  answerQuickNote();
}

const page = currentPage();
if (page === 'screen') exposeScreen();
else if (page === 'update') exposeUpdate();
else if (page === 'hub') prepareHub();
