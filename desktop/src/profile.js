// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const config = require('./config');
const { log } = require('./log');

function isDirectory(dir) {
  try {
    return fs.lstatSync(dir).isDirectory();
  } catch {
    return false;
  }
}

function adoptLegacyFolder(appData, target) {
  if (fs.existsSync(target)) return target;
  const names = new Set((config.brand.previousNames || []).flatMap((name) => [name, name.toLowerCase()]));
  for (const name of names) {
    const legacy = path.join(appData, name);
    if (!isDirectory(legacy)) continue;
    try {
      fs.renameSync(legacy, target);
      log(`moved ${legacy} to ${target}`);
      return target;
    } catch (error) {
      if (fs.existsSync(target)) return target;
      log(`could not move ${legacy} to ${target} (${error.code || error.message}), using the old folder for now`);
      return legacy;
    }
  }
  return target;
}

function chooseUserData() {
  const devAppData = config.devSetting('HUB_DEV_APP_DATA');
  if (config.isDev && !(devAppData && path.isAbsolute(devAppData))) {
    app.setPath('userData', path.join(app.getPath('appData'), `${config.brand.name} Dev`));
    return;
  }
  const appData = config.isDev ? devAppData : app.getPath('appData');
  fs.mkdirSync(appData, { recursive: true });
  app.setPath('userData', adoptLegacyFolder(appData, path.join(appData, config.brand.name)));
}

module.exports = { chooseUserData };
