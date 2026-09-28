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
let home = null;

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
if (process.platform === 'darwin') Object.defineProperty(process, 'platform', { value: 'linux' });
os.homedir = () => home;
console.log = () => {};

const copy = require('../src/copy');
const legacy = require('../src/legacy');
const processes = require('../src/processes');
const store = require('../src/store');
const { takeOver } = require('../src/takeover');

const importLegacyData = legacy.importLegacyData;
let root;
let dataDir;
let statuses;
const originalHome = process.env.HOME;
const originalProfile = process.env.USERPROFILE;

test.beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'takeover-'));
  fs.writeFileSync(path.join(root, '.env'), '');
  fs.writeFileSync(path.join(root, '.flaskenv'), '');
  home = path.join(root, 'home', 'ben');
  shellDocuments = path.join(home, 'Dokumente');
  process.env.HOME = home;
  process.env.USERPROFILE = home;
  delete process.env.SECRET_KEY;
  dataDir = path.join(root, 'config', brand.name, 'data');
  statuses = [];
  answers.length = 0;
  questions.length = 0;
  processes.isPortTaken = async () => false;
  processes.findPython = async () => null;
  legacy.importLegacyData = importLegacyData;
  store.set('earlierDataDeclined', null);
});

test.afterEach(() => {
  for (const [name, value] of [['HOME', originalHome], ['USERPROFILE', originalProfile]]) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
  fs.rmSync(root, { recursive: true, force: true });
});

function makeLegacy(folder, { content = 'db', env = `SECRET_KEY=${KEY}\n` } = {}) {
  fs.mkdirSync(path.join(folder, 'data'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'data', 'hub.db'), content);
  if (env !== null) fs.writeFileSync(path.join(folder, '.env'), env);
  return folder;
}

function unusedProfile() {
  const { DatabaseSync } = require('node:sqlite');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, '.secret_key'), 'a'.repeat(64));
  fs.writeFileSync(path.join(dataDir, '.api_token'), 'ENC2:frisch');
  const connection = new DatabaseSync(path.join(dataDir, 'hub.db'));
  connection.exec('CREATE TABLE hub_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT)');
  connection.close();
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
  assert.ok(question.detail.endsWith(`Fängst du neu an, fragt ${brand.name} nicht noch einmal.`));
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

test('halts with its own message while another program holds the port', async () => {
  makeLegacy(oldAppFolder());
  processes.isPortTaken = async () => true;
  assert.deepEqual(await run(), { problem: { outcome: 'busy', name: previous } });
  assert.equal(questions.length, 0);
  assert.equal(fs.existsSync(dataDir), false);
  const screen = copy.problem('takeover', { outcome: 'busy', name: previous });
  assert.equal(screen.message, `Vielleicht läuft ${previous} noch. Beende ${previous} und versuch es noch einmal, dann übernimmt ${brand.name} deine Daten.`);
  assert.deepEqual(Object.keys(screen.actions), ['retry']);
});

test('halts when the port gets taken while the question is open', async () => {
  makeLegacy(oldAppFolder());
  answers.push(0);
  let checks = 0;
  processes.isPortTaken = async () => (checks += 1) > 1;
  const result = await run();
  assert.equal(result.problem.outcome, 'busy');
  assert.equal(fs.existsSync(dataDir), false);
});

test('does not ask once the new data folder is in use', async () => {
  makeLegacy(oldAppFolder());
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'notizen.json'), 'neu');
  assert.equal(await run(), null);
  assert.equal(questions.length, 0);
});

test('a Python lookup that throws does not cost the import', async () => {
  makeLegacy(oldAppFolder());
  processes.findPython = async () => { throw Object.assign(new Error('spawn EINVAL'), { code: 'EINVAL' }); };
  answers.push(0);
  assert.equal(await run(), null);
  assert.equal(fs.readFileSync(path.join(dataDir, '.secret_key'), 'utf8'), KEY);
});

test('an error after the user said yes shows a problem instead of starting empty', async () => {
  makeLegacy(oldAppFolder());
  legacy.importLegacyData = async () => { throw Object.assign(new Error('kaputt'), { code: 'EIO' }); };
  answers.push(0);
  const result = await run();
  assert.equal(result.problem.outcome, 'failed');
  assert.equal(result.problem.code, 'EIO');
  assert.equal(copy.problem('takeover', result.problem).detail, 'Fehler EIO');
});

test('runs only one takeover at a time', async () => {
  makeLegacy(oldAppFolder());
  answers.push(0, 0);
  const [first, second] = await Promise.all([run(), run()]);
  assert.equal(first, null);
  assert.equal(second, null);
  assert.equal(questions.length, 1);
});

test('offers the old data to a profile an earlier start set up but nobody used', async () => {
  const folder = makeLegacy(oldAppFolder());
  unusedProfile();
  answers.push(0);
  assert.equal(await run(), null);
  assert.equal(questions.length, 1);
  assert.equal(fs.readFileSync(path.join(dataDir, 'hub.db'), 'utf8'), 'db');
  assert.equal(fs.readFileSync(path.join(dataDir, '.secret_key'), 'utf8'), KEY);
  assert.equal(fs.existsSync(path.join(dataDir, '.api_token')), false);
  assert.equal(fs.readFileSync(path.join(folder, 'data', 'hub.db'), 'utf8'), 'db');
});

test('remembers a fresh start for an unused profile but asks again once the data folder is gone', async () => {
  makeLegacy(oldAppFolder());
  answers.push(1);
  assert.equal(await run(), null);
  unusedProfile();
  assert.equal(await run(), null);
  assert.equal(questions.length, 1);
  fs.rmSync(dataDir, { recursive: true });
  answers.push(0);
  assert.equal(await run(), null);
  assert.equal(questions.length, 2);
  assert.equal(fs.readFileSync(path.join(dataDir, '.secret_key'), 'utf8'), KEY);
  assert.equal(store.get('earlierDataDeclined'), undefined);
});

test('reports settings it cannot read and names the file', async () => {
  const folder = makeLegacy(oldAppFolder(), { env: `SECRET_KEY="${KEY}\n` });
  answers.push(0);
  const result = await run();
  assert.deepEqual(result, { problem: { outcome: 'unclear', file: path.join(folder, '.env'), name: previous, folder } });
  assert.equal(fs.existsSync(dataDir), false);
  const screen = copy.problem('takeover', result.problem);
  assert.equal(screen.heading, `Die Daten aus ${previous} wurden nicht übernommen.`);
  assert.ok(screen.message.startsWith('Die Datei „.env“ lässt sich nicht eindeutig lesen.'));
  assert.ok(screen.message.endsWith('Beim nächsten Versuch kannst du auch neu anfangen.'));
  assert.equal(screen.detail, path.join(folder, '.env'));
  assert.deepEqual(Object.keys(screen.actions), ['retry', 'log']);
});

test('every German text avoids dashes and reassures that the old folder stays', () => {
  const one = [{ folder: '/a', name: previous, newest: Date.UTC(2026, 2, 14, 12) }];
  const two = [...one, { folder: '/b', name: previous, newest: null }];
  const outcomes = ['unclear', 'unsupported', 'weak', 'busy', 'failed'];
  const screens = outcomes.map((outcome) => copy.problem('takeover', { outcome, name: previous, code: 'EIO', file: '/a/.env' }));
  const space = copy.problem('takeover', { outcome: 'space', name: previous, needed: 3.4 * 1024 ** 3, free: 0 });
  const port = copy.problem('port');
  const texts = [copy.takeover.question(one), copy.takeover.question(two), ...screens, space, port, copy.takeover.importing(previous)];
  const dashes = new RegExp(`[${String.fromCharCode(0x2013, 0x2014)}]`);
  for (const text of texts) assert.doesNotMatch(JSON.stringify(text), dashes);
  assert.ok(copy.takeover.question(two).detail.includes('2. „/b“\n'));
  assert.equal(space.message, `${brand.name} braucht dafür etwa 3,4 GB freien Speicherplatz, frei sind nur 0 KB. Gib etwas Platz frei und versuch es noch einmal. Der alte Ordner ist unverändert.`);
  assert.equal(screens[4].detail, 'Fehler EIO');
  assert.ok(screens[4].message.startsWith('Der alte Ordner ist unverändert.'));
  assert.ok(screens[2].message.includes('Der alte Ordner ist unverändert.'));
  assert.ok(copy.problem('takeover', { outcome: 'unsupported', name: previous, file: null }).message.startsWith('Der SECRET_KEY aus deiner Umgebung'));
  assert.ok(port.message.includes(`zum Beispiel ${previous} oder ein älteres ${brand.name}`));
});
