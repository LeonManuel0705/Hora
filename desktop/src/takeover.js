// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app, dialog } = require('electron');
const os = require('os');
const path = require('path');
const config = require('./config');
const copy = require('./copy');
const legacy = require('./legacy');
const { log } = require('./log');
const processes = require('./processes');
const store = require('./store');

const DECLINED = 'earlierDataDeclined';

let running = null;

function shellDocuments() {
  try {
    return app.getPath('documents');
  } catch (error) {
    log('the documents folder is unknown:', error.message);
    return null;
  }
}

function candidateFolders() {
  const names = config.brand.previousNames || [];
  if (config.isDev) {
    const documents = config.devSetting('HUB_DEV_LEGACY_DOCUMENTS');
    return documents && path.isAbsolute(documents) ? legacy.candidateFolders({ documents, names }) : [];
  }
  if (process.platform !== 'win32' && process.platform !== 'linux') return [];
  return legacy.candidateFolders({
    platform: process.platform,
    env: process.env,
    homedir: os.homedir(),
    documents: shellDocuments(),
    names,
  });
}

function whenShown(win) {
  if (!win || win.isDestroyed() || win.isVisible()) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, 5000);
    win.once('show', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function ask(getWindow, found) {
  await whenShown(getWindow());
  const question = copy.takeover.question(found);
  const options = {
    type: 'question',
    title: config.brand.name,
    message: question.message,
    detail: question.detail,
    buttons: question.buttons,
    defaultId: 0,
    cancelId: question.buttons.length - 1,
    noLink: true,
  };
  const win = getWindow();
  const visible = win && !win.isDestroyed() && win.isVisible();
  const { response } = await (visible ? dialog.showMessageBox(win, options) : dialog.showMessageBox(options));
  if (response >= 0 && response < found.length) return found[response];
  return response === found.length ? 'fresh' : 'quit';
}

const portFree = async () => !(await processes.isPortTaken(config.port));

async function attempt({ dataDir, getWindow, onStatus, withoutEncryptedFrom = null }) {
  const target = path.dirname(dataDir);
  await legacy.cleanUp(target);
  const state = await legacy.dataState(dataDir).catch(() => 'used');
  if (state === 'used' || (state === 'unused' && store.get(DECLINED))) return null;
  let found;
  try {
    found = await legacy.findLegacyFolders(candidateFolders(), { target, log });
  } catch (error) {
    log('looking for earlier data failed:', error);
    return null;
  }
  if (!found.length) {
    if (!withoutEncryptedFrom) return null;
    log(`${withoutEncryptedFrom} is gone, nothing was taken over`);
    return { problem: { outcome: 'gone', name: path.basename(withoutEncryptedFrom), folder: withoutEncryptedFrom } };
  }
  log(`data from an earlier version found in ${found.map((item) => item.folder).join(', ')}`);
  const chosen = withoutEncryptedFrom ? found.find((item) => item.folder === withoutEncryptedFrom) : null;
  if (!(await portFree())) {
    log(`port ${config.port} is taken, the earlier data waits until it is free`);
    const partial = chosen ? { folder: chosen.folder, withoutEncrypted: true } : {};
    return { problem: { outcome: 'busy', name: (chosen || found[0]).name, ...partial } };
  }
  let choice = chosen;
  if (choice) {
    log(`taking over ${choice.folder} without its encrypted files, as chosen`);
  } else {
    try {
      choice = await ask(getWindow, found);
    } catch (error) {
      log('the question about the earlier data could not be shown:', error);
      return null;
    }
  }
  if (choice === 'quit') {
    log('quitting before a decision about the earlier data');
    return { quit: true };
  }
  if (choice === 'fresh') {
    log('starting fresh, the earlier data stays where it is');
    store.set(DECLINED, true, { now: true });
    return null;
  }
  onStatus(copy.takeover.importing(choice.name));
  const withoutEncrypted = choice === chosen;
  let result;
  try {
    result = await legacy.importLegacyData({
      legacy: choice.folder,
      target,
      python: () => processes.findPython(choice.folder),
      portFree,
      withoutEncrypted,
      log,
    });
  } catch (error) {
    log('taking over the earlier data failed:', error);
    result = { outcome: 'failed', code: error && error.code ? String(error.code) : null };
  }
  const notes = [
    result.key && `key ${result.key}`,
    result.replaced && 'unused profile replaced',
    result.leftOut && `encrypted files left out: ${result.leftOut}`,
    result.reason,
    result.code,
  ].filter(Boolean);
  log(`import from ${choice.folder}: ${result.outcome}${notes.length ? ` (${notes.join(', ')})` : ''}`);
  if (result.outcome === 'imported') store.set(DECLINED, null, { now: true });
  if (result.outcome === 'imported' || result.outcome === 'skipped') return null;
  return { problem: { ...result, name: choice.name, folder: choice.folder, ...(withoutEncrypted ? { withoutEncrypted } : {}) } };
}

function takeOver(options) {
  if (!running) {
    running = attempt(options).finally(() => {
      running = null;
    });
  }
  return running;
}

module.exports = { takeOver };
