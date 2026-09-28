// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const brand = require('../brand.json');

const [previous] = brand.previousNames;
const answers = [];
const questions = [];

const electron = {
  app: {
    isPackaged: false,
    getPath(name) {
      throw new Error(`a development run must not ask for ${name}`);
    },
  },
  dialog: {
    async showMessageBox(...args) {
      questions.push(args[args.length - 1]);
      return { response: answers.shift(), checkboxChecked: false };
    },
  },
};

const load = Module._load;
Module._load = function loadWithElectron(request, ...rest) {
  return request === 'electron' ? electron : load.call(this, request, ...rest);
};
console.log = () => {};

const processes = require('../src/processes');
const { takeOver } = require('../src/takeover');

test('a development run only looks where HUB_DEV_LEGACY_DOCUMENTS points', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'takeover-dev-'));
  try {
    fs.writeFileSync(path.join(root, '.env'), '');
    fs.writeFileSync(path.join(root, '.flaskenv'), '');
    const documents = path.join(root, 'Dokumente');
    fs.mkdirSync(path.join(documents, previous, 'data'), { recursive: true });
    fs.writeFileSync(path.join(documents, previous, 'data', 'hub.db'), 'db');
    const dataDir = path.join(root, 'profil', 'data');
    const run = () => takeOver({ dataDir, getWindow: () => null, onStatus: () => {} });
    processes.isPortTaken = async () => false;
    processes.findPython = async () => null;

    delete process.env.HUB_DEV_LEGACY_DOCUMENTS;
    assert.equal(await run(), null);
    process.env.HUB_DEV_LEGACY_DOCUMENTS = 'Dokumente';
    assert.equal(await run(), null);
    assert.equal(questions.length, 0);

    process.env.HUB_DEV_LEGACY_DOCUMENTS = documents;
    answers.push(0);
    assert.equal(await run(), null);
    assert.equal(questions.length, 1);
    assert.equal(fs.readFileSync(path.join(dataDir, 'hub.db'), 'utf8'), 'db');
  } finally {
    delete process.env.HUB_DEV_LEGACY_DOCUMENTS;
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 5 });
  }
});
