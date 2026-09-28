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
  const { response } = await (win && !win.isDestroyed() ? dialog.showMessageBox(win, options) : dialog.showMessageBox(options));
  if (response >= 0 && response < found.length) return found[response];
  return response === found.length ? 'fresh' : 'quit';
}

async function takeOver({ dataDir, getWindow, onStatus }) {
  const target = path.dirname(dataDir);
  await legacy.cleanUp(target);
  if (!(await legacy.isFresh(dataDir))) return null;
  const folders = candidateFolders();
  if (!folders.length) return null;
  const found = await legacy.findLegacyFolders(folders, { target });
  if (!found.length) return null;
  log(`data from an earlier version found in ${found.map((item) => item.folder).join(', ')}`);
  if (await processes.isPortTaken(config.port)) {
    log(`port ${config.port} is taken, the earlier data waits until it is free`);
    return null;
  }
  const choice = await ask(getWindow, found);
  if (choice === 'quit') {
    log('quitting before a decision about the earlier data');
    return { quit: true };
  }
  if (choice === 'fresh') {
    log('starting fresh, the earlier data stays where it is');
    return null;
  }
  onStatus(copy.takeover.importing(choice.name));
  const python = await processes.findPython(choice.folder);
  log(python ? `checking the earlier settings with ${python}` : 'no Python found, reading the earlier settings without it');
  const result = await legacy.importLegacyData({ legacy: choice.folder, target, python });
  log(`import from ${choice.folder}: ${result.outcome}${result.key ? `, key ${result.key}` : ''}${result.code ? ` (${result.code})` : ''}`);
  if (result.outcome === 'imported' || result.outcome === 'skipped') return null;
  return { problem: { ...result, name: choice.name, folder: choice.folder, file: path.join(choice.folder, '.env') } };
}

module.exports = { takeOver };
