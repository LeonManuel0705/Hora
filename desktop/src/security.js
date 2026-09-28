// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { BrowserWindow, Menu, clipboard, shell } = require('electron');
const config = require('./config');
const copy = require('./copy');
const { log } = require('./log');
const rules = require('./rules');

const EXTERNAL_PROTOCOLS = new Set(['http:', 'https:', 'mailto:']);
const HUB_PERMISSIONS = new Set(['notifications', 'clipboard-sanitized-write']);

const parse = rules.parseUrl;
const isHubUrl = (url) => rules.isHubUrl(url, config.hubOrigin);
const isHubOrigin = (value) => rules.isHubOrigin(value, config.hubOrigin);

let lastExternal = { url: null, at: 0 };

function openExternally(url) {
  const parsed = parse(url);
  if (!parsed || !EXTERNAL_PROTOCOLS.has(parsed.protocol)) return false;
  const now = Date.now();
  if (lastExternal.url === parsed.href && now - lastExternal.at < 2000) return true;
  lastExternal = { url: parsed.href, at: now };
  shell.openExternal(parsed.href).catch((error) => log('could not open link:', error.message));
  return true;
}

function hardenSession(ses) {
  ses.setPermissionRequestHandler((_contents, permission, callback, details) => {
    callback(HUB_PERMISSIONS.has(permission) && isHubOrigin(details && details.requestingUrl));
  });
  ses.setPermissionCheckHandler((_contents, permission, requestingOrigin) =>
    HUB_PERMISSIONS.has(permission) && isHubOrigin(requestingOrigin));
  ses.setDevicePermissionHandler(() => false);
  if (process.platform === 'linux') ses.setSpellCheckerEnabled(false);
}

function contextMenuFor(contents, params) {
  const items = [];
  const flags = params.editFlags || {};
  if (params.isEditable && params.misspelledWord) {
    for (const suggestion of (params.dictionarySuggestions || []).slice(0, 4)) {
      items.push({ label: suggestion, click: () => contents.replaceMisspelling(suggestion) });
    }
    items.push({ label: copy.menu.learnSpelling, click: () => contents.session.addWordToSpellCheckerDictionary(params.misspelledWord) });
    items.push({ type: 'separator' });
  }
  if (params.isEditable) {
    items.push(
      { label: copy.menu.undo, role: 'undo', enabled: Boolean(flags.canUndo) },
      { label: copy.menu.redo, role: 'redo', enabled: Boolean(flags.canRedo) },
      { type: 'separator' },
      { label: copy.menu.cut, role: 'cut', enabled: Boolean(flags.canCut) },
      { label: copy.menu.copy, role: 'copy', enabled: Boolean(flags.canCopy) },
      { label: copy.menu.paste, role: 'paste', enabled: Boolean(flags.canPaste) },
      { type: 'separator' },
      { label: copy.menu.selectAll, role: 'selectAll', enabled: Boolean(flags.canSelectAll) },
    );
  } else if (params.selectionText && params.selectionText.trim()) {
    items.push({ label: copy.menu.copy, role: 'copy' });
  }
  const link = parse(params.linkURL || '');
  if (link && EXTERNAL_PROTOCOLS.has(link.protocol) && !isHubUrl(link.href)) {
    if (items.length) items.push({ type: 'separator' });
    items.push({ label: copy.menu.copyLink, click: () => clipboard.writeText(link.href) });
  }
  return items;
}

function hardenContents(contents, { openHubUrl }) {
  contents.on('will-attach-webview', (event) => event.preventDefault());

  contents.setWindowOpenHandler(({ url }) => {
    if (isHubUrl(url)) openHubUrl(url);
    else openExternally(url);
    return { action: 'deny' };
  });

  contents.on('will-navigate', (event) => {
    if (isHubUrl(event.url)) return;
    event.preventDefault();
    openExternally(event.url);
  });

  contents.on('will-redirect', (event) => {
    if (isHubUrl(event.url)) return;
    event.preventDefault();
    if (event.isMainFrame) openExternally(event.url);
  });

  contents.on('context-menu', (_event, params) => {
    const items = contextMenuFor(contents, params);
    if (!items.length) return;
    const window = BrowserWindow.fromWebContents(contents) || BrowserWindow.getFocusedWindow();
    Menu.buildFromTemplate(items).popup(window ? { window } : {});
  });
}

module.exports = { hardenContents, hardenSession, isHubUrl, openExternally };
