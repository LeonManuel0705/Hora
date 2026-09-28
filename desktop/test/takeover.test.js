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
const KEY = '0123456789abcdef0123456789abcdef0123456789abcdef';
const answers = [];
const questions = [];
let shellDocuments = null;

const electron = {
  app: {
    isPackaged: true,
    getPath(name) {
      if (name !== 'documents') throw new Error(`unexpected path ${name}`);
      return shellDocuments;
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
Object.defineProperty(process, 'platform', { value: 'linux' });
console.log = () => {};

const copy = require('../src/copy');
const processes = require('../src/processes');
const { takeOver } = require('../src/takeover');

let root;
let home;
let dataDir;
let statuses;
const originalHome = process.env.HOME;

test.beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'takeover-'));
  home = path.join(root, 'home', 'ben');
  shellDocuments = path.join(home, 'Dokumente');
  process.env.HOME = home;
  dataDir = path.join(root, 'config', brand.name, 'data');
  statuses = [];
  answers.length = 0;
  questions.length = 0;
  processes.isPortTaken = async () => false;
  processes.findPython = async () => null;
});

test.afterEach(() => {
  process.env.HOME = originalHome;
  fs.rmSync(root, { recursive: true, force: true });
});

function makeLegacy(folder, { content = 'db', env = `SECRET_KEY=${KEY}\n` } = {}) {
  fs.mkdirSync(path.join(folder, 'data'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'data', 'hub.db'), content);
  if (env !== null) fs.writeFileSync(path.join(folder, '.env'), env);
  return folder;
}

const run = () => takeOver({ dataDir, getWindow: () => null, onStatus: (status) => statuses.push(status) });
const oldAppFolder = () => path.join(home, 'Documents', previous);

test('asks once in German and imports the folder on consent', async () => {
  const folder = makeLegacy(oldAppFolder());
  answers.push(0);
  assert.equal(await run(), null);
  assert.equal(questions.length, 1);
  const [question] = questions;
  assert.equal(question.message, `Daten aus ${previous} gefunden`);
  assert.deepEqual(question.buttons, ['Übernehmen', 'Neu anfangen', 'Beenden']);
  assert.equal(question.defaultId, 0);
  assert.equal(question.cancelId, 2);
  assert.equal(question.noLink, true);
  assert.equal(question.title, brand.name);
  assert.ok(question.detail.includes(`„${folder}“`));
  assert.ok(question.detail.includes(`als ${brand.name} noch ${previous} hieß`));
  assert.deepEqual(statuses, [copy.takeover.importing(previous)]);
  assert.equal(fs.readFileSync(path.join(dataDir, 'hub.db'), 'utf8'), 'db');
  assert.equal(fs.readFileSync(path.join(dataDir, '.secret_key'), 'utf8'), KEY);
  assert.equal(fs.readFileSync(path.join(folder, 'data', 'hub.db'), 'utf8'), 'db');
});

test('offers every folder with its date when the documents folder was moved', async () => {
  makeLegacy(oldAppFolder(), { content: 'alt' });
  const moved = makeLegacy(path.join(shellDocuments, previous), { content: 'verschoben' });
  answers.push(1);
  assert.equal(await run(), null);
  const [question] = questions;
  assert.deepEqual(question.buttons, ['Ordner 1 übernehmen', 'Ordner 2 übernehmen', 'Neu anfangen', 'Beenden']);
  assert.equal(question.cancelId, 3);
  assert.ok(question.detail.includes('in zwei Ordnern'));
  assert.ok(question.detail.includes(`1. „${oldAppFolder()}“, zuletzt geändert am `));
  assert.ok(question.detail.includes(`2. „${moved}“, zuletzt geändert am `));
  assert.match(question.detail, /am \d\d\.\d\d\.\d{4}/);
  assert.equal(fs.readFileSync(path.join(dataDir, 'hub.db'), 'utf8'), 'verschoben');
});

test('starts fresh and leaves everything as it was', async () => {
  const folder = makeLegacy(oldAppFolder());
  answers.push(1);
  assert.equal(await run(), null);
  assert.equal(fs.existsSync(dataDir), false);
  assert.deepEqual(statuses, []);
  assert.deepEqual(fs.readdirSync(path.join(folder, 'data')), ['hub.db']);
});

test('quits without a decision when the question is closed', async () => {
  makeLegacy(oldAppFolder());
  answers.push(2);
  assert.deepEqual(await run(), { quit: true });
  assert.equal(fs.existsSync(dataDir), false);
});

test('does not ask while another program holds the port', async () => {
  makeLegacy(oldAppFolder());
  processes.isPortTaken = async () => true;
  assert.equal(await run(), null);
  assert.equal(questions.length, 0);
  assert.equal(fs.existsSync(dataDir), false);
});

test('does not ask once the new data folder is in use', async () => {
  makeLegacy(oldAppFolder());
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'hub.db'), 'neu');
  assert.equal(await run(), null);
  assert.equal(questions.length, 0);
});

test('reports settings it cannot read and names the file', async () => {
  const folder = makeLegacy(oldAppFolder(), { env: `SECRET_KEY="${KEY}\n` });
  answers.push(0);
  const result = await run();
  assert.deepEqual(result, { problem: { outcome: 'unclear', name: previous, folder, file: path.join(folder, '.env') } });
  assert.equal(fs.existsSync(dataDir), false);
  const screen = copy.problem('takeover', result.problem);
  assert.equal(screen.heading, `Die Daten aus ${previous} wurden nicht übernommen.`);
  assert.equal(screen.detail, path.join(folder, '.env'));
  assert.deepEqual(Object.keys(screen.actions), ['retry', 'log']);
});

test('every German text avoids dashes and reassures that the old folder stays', () => {
  const one = [{ folder: '/a', name: previous, newest: Date.UTC(2026, 2, 14, 12) }];
  const two = [...one, { folder: '/b', name: previous, newest: null }];
  const screens = ['unclear', 'unsupported', 'failed'].map((outcome) => copy.problem('takeover', { outcome, name: previous, code: 'EIO' }));
  const space = copy.problem('takeover', { outcome: 'space', name: previous, needed: 3.4 * 1024 ** 3, free: 512 * 1024 ** 2 });
  const texts = [copy.takeover.question(one), copy.takeover.question(two), ...screens, space, copy.takeover.importing(previous)];
  const dashes = new RegExp(`[${String.fromCharCode(0x2013, 0x2014)}]`);
  for (const text of texts) assert.doesNotMatch(JSON.stringify(text), dashes);
  assert.ok(copy.takeover.question(two).detail.includes('2. „/b“\n'));
  assert.equal(space.message, `Die Daten aus ${previous} brauchen etwa 3,4 GB, frei sind nur 512,0 MB. Gib etwas Platz frei und versuch es noch einmal. Der alte Ordner ist unverändert.`);
  assert.equal(screens[2].detail, 'Fehler EIO');
  assert.ok(screens[2].message.startsWith('Der alte Ordner ist unverändert.'));
});
