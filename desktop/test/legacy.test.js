// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const brand = require('../brand.json');
const legacy = require('../src/legacy');

const KEY = '0123456789abcdef0123456789abcdef0123456789abcdef';
const OTHER_KEY = 'fedcba9876543210fedcba9876543210fedcba9876543210';
const OLD_FILE_KEY = 'f'.repeat(64);
const [previous] = brand.previousNames;
const database = `${previous.toLowerCase()}.db`;
const prefix = previous.toUpperCase().replace(/[^A-Z0-9]+/g, '_');
const posix = process.platform !== 'win32';
const repository = path.resolve(__dirname, '..', '..');
const NBSP = String.fromCharCode(0xa0);
const GRADES = 'school_grades.json';

function pythonWith(modules, options = {}) {
  const candidates = [process.env.HUB_TEST_PYTHON, path.join(repository, 'venv', 'bin', 'python'), 'python3', 'python'];
  for (const candidate of candidates.filter(Boolean)) {
    const check = spawnSync(candidate, [...(options.isolated ? ['-I'] : []), '-c', `import ${modules}`], { cwd: options.cwd, encoding: 'utf8' });
    if (check.status === 0) return candidate;
  }
  return null;
}

const python = pythonWith('dotenv', { isolated: true });
const noPython = python ? false : 'python-dotenv ist hier nicht installiert';
const backendPython = pythonWith('dotenv, cryptography', { cwd: repository });

let root;
let documents;
let folder;
let target;
let logs;

test.beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'legacy-import-'));
  fs.writeFileSync(path.join(root, '.env'), '');
  fs.writeFileSync(path.join(root, '.flaskenv'), '');
  documents = path.join(root, 'Documents');
  folder = path.join(documents, previous);
  target = path.join(root, 'profile');
  logs = [];
  fs.mkdirSync(path.join(folder, 'data', 'nested'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'data', database), 'db');
  fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), OLD_FILE_KEY);
  fs.writeFileSync(path.join(folder, 'data', 'nested', 'school_tests.json'), '[]');
  fs.writeFileSync(path.join(folder, 'data', GRADES), 'NEXUS2:c2FsdA==:gAAAAABnoten');
  writeEnv(`FLASK_ENV=development\nSECRET_KEY=${KEY}\n${prefix}_DATA_DIR=/woanders\n${prefix}_PORT=6060\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n`);
});

test.afterEach(() => {
  if (posix) spawnSync('chmod', ['-R', 'u+rwX', root]);
  fs.rmSync(root, { recursive: true, force: true, maxRetries: 5 });
});

function writeEnv(text, name = '.env', where = folder) {
  fs.writeFileSync(path.join(where, name), text);
}

function nothingEncrypted() {
  fs.rmSync(path.join(folder, 'data', GRADES));
}

const imported = (options = {}) => legacy.importLegacyData({
  legacy: folder,
  target,
  env: {},
  log: (...parts) => logs.push(parts.join(' ')),
  ...options,
});
const checked = (options = {}) => imported({ python, ...options });
const newData = (...parts) => path.join(target, 'data', ...parts);
const oldData = (...parts) => path.join(folder, 'data', ...parts);
const keyFile = () => fs.readFileSync(newData(legacy.KEY_FILE), 'utf8');
const exists = (file) => fs.existsSync(file);
const leftovers = () => (exists(target) ? fs.readdirSync(target).filter((name) => name.startsWith('.data-import-')) : []);
const find = (options = {}) => legacy.findLegacyFolders(legacy.candidateFolders({ documents, names: [previous], ...options }), { target, log: (...parts) => logs.push(parts.join(' ')) });
const outcome = async (options) => (await imported(options)).outcome;
const envFile = () => path.join(folder, '.env');

function makeLegacy(where, content = 'db') {
  fs.mkdirSync(path.join(where, 'data'), { recursive: true });
  fs.writeFileSync(path.join(where, 'data', database), content);
}

function isLink(file) {
  try {
    return fs.lstatSync(file).isSymbolicLink();
  } catch {
    return false;
  }
}

function snapshot(dir) {
  const entries = [];
  const walk = (current) => {
    for (const name of fs.readdirSync(current).sort()) {
      const item = path.join(current, name);
      const info = fs.lstatSync(item);
      entries.push([path.relative(dir, item), info.mode, info.size, info.mtimeMs]);
      if (info.isDirectory()) walk(item);
    }
  };
  walk(dir);
  return entries;
}

function sizeOf(dir) {
  return fs.readdirSync(dir).reduce((total, name) => {
    const info = fs.lstatSync(path.join(dir, name));
    return total + (info.isDirectory() ? sizeOf(path.join(dir, name)) : info.size);
  }, 0);
}

function withDatabase(file, change) {
  const { DatabaseSync } = require('node:sqlite');
  const connection = new DatabaseSync(file);
  try {
    change(connection);
  } finally {
    connection.close();
  }
}

function unusedProfile() {
  fs.mkdirSync(newData(), { recursive: true });
  fs.writeFileSync(newData(legacy.KEY_FILE), 'a'.repeat(64));
  fs.writeFileSync(newData('.api_token'), 'ENC2:frisch');
  withDatabase(newData('hub.db'), (db) => db.exec([
    'CREATE TABLE hub_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT)',
    'CREATE TABLE ui_store (key TEXT PRIMARY KEY, value TEXT)',
    "CREATE TABLE hub_timetable_settings (id INTEGER PRIMARY KEY AUTOINCREMENT, has_ab_weeks INTEGER DEFAULT 1, grade_system TEXT DEFAULT 'points', theme TEXT DEFAULT 'dark', reference_date TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, tour_state TEXT, user_id TEXT)",
  ].join('; ')));
}

async function retryingRename(from, to) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await fs.promises.rename(from, to);
      return;
    } catch (error) {
      if (attempt >= 10 || !['EPERM', 'EACCES', 'EBUSY'].includes(error.code)) throw error;
      await new Promise((resolve) => setTimeout(resolve, 100 * attempt));
    }
  }
}

test('finds the old folder while the new data folder is missing or empty', async () => {
  assert.deepEqual((await find()).map((item) => item.folder), [folder]);
  assert.equal(await legacy.isFresh(newData()), true);
  fs.mkdirSync(newData(), { recursive: true });
  assert.equal(await legacy.isFresh(newData()), true);
});

test('leaves a new data folder with content alone', async () => {
  fs.mkdirSync(newData(), { recursive: true });
  fs.writeFileSync(newData('notizen.json'), 'neu');
  assert.equal(await legacy.isFresh(newData()), false);
  assert.deepEqual(await imported(), { outcome: 'skipped' });
  assert.equal(fs.readFileSync(newData('notizen.json'), 'utf8'), 'neu');
});

test('treats a data path that is a file or a link as used', { skip: !posix }, async () => {
  fs.mkdirSync(target, { recursive: true });
  fs.symlinkSync(root, newData());
  assert.equal(await legacy.isFresh(newData()), false);
  fs.unlinkSync(newData());
  fs.writeFileSync(newData(), '');
  assert.equal(await legacy.isFresh(newData()), false);
});

test('only offers an old folder whose data holds its database', async () => {
  fs.rmSync(oldData(database));
  assert.deepEqual(await find(), []);
  assert.ok(logs.some((line) => line.includes('holds no database')));
  fs.writeFileSync(oldData('hub.db'), 'db');
  assert.deepEqual((await find()).map((item) => item.folder), [folder]);
  fs.rmSync(oldData(), { recursive: true });
  fs.mkdirSync(oldData());
  assert.deepEqual(await find(), []);
});

test('ignores an old folder or data folder that is only a link, and says so', { skip: !posix }, async () => {
  const real = path.join(root, 'elsewhere');
  fs.mkdirSync(real);
  fs.renameSync(folder, path.join(real, previous));
  fs.symlinkSync(path.join(real, previous), folder);
  assert.deepEqual(await find(), []);
  assert.ok(logs.some((line) => line.includes('the folder is link')));
  fs.unlinkSync(folder);
  fs.mkdirSync(folder);
  fs.symlinkSync(path.join(real, previous, 'data'), path.join(folder, 'data'));
  assert.deepEqual(await find(), []);
});

test('Windows layout: the folder the old app used comes first, the redirected Documents folder second', async () => {
  const profile = path.join(root, 'Users', 'Ben');
  const redirected = path.join(profile, 'OneDrive', 'Dokumente');
  const folders = legacy.candidateFolders({ platform: 'win32', env: { USERPROFILE: profile }, homedir: profile, documents: redirected, names: [previous] });
  assert.deepEqual(folders, [path.join(profile, 'Documents', previous), path.join(redirected, previous)]);
  makeLegacy(path.join(redirected, previous));
  assert.deepEqual((await legacy.findLegacyFolders(folders, { target })).map((item) => item.folder), [path.join(redirected, previous)]);
  makeLegacy(path.join(profile, 'Documents', previous));
  const found = await legacy.findLegacyFolders(folders, { target });
  assert.deepEqual(found.map((item) => item.folder), folders);
  assert.equal(found[0].name, previous);
  assert.equal(found[0].files, 1);
  assert.equal(typeof found[0].newest, 'number');
});

test('Windows layout: HOME wins over USERPROFILE, as it did in the old app', () => {
  const home = path.join(root, 'home');
  const profile = path.join(root, 'Users', 'Ben');
  const folders = legacy.candidateFolders({ platform: 'win32', env: { HOME: home, USERPROFILE: profile }, homedir: profile, names: [previous] });
  assert.deepEqual(folders, [path.join(home, 'Documents', previous), path.join(profile, 'Documents', previous)]);
});

test('Windows layout: folders that differ only in case are one folder', () => {
  const profile = path.join(root, 'Users', 'Ben');
  const folders = legacy.candidateFolders({ platform: 'win32', env: { USERPROFILE: profile }, homedir: profile.toUpperCase(), documents: path.join(profile, 'documents'), names: [previous] });
  assert.deepEqual(folders, [path.join(profile, 'Documents', previous)]);
  const linux = legacy.candidateFolders({ platform: 'linux', env: { HOME: profile }, homedir: profile.toUpperCase(), names: [previous] });
  assert.equal(linux.length, 2);
});

test('Linux layout: the Documents folder in HOME first, then the XDG documents folder', async () => {
  const home = path.join(root, 'home', 'ben');
  const xdg = path.join(home, 'Dokumente');
  const folders = legacy.candidateFolders({ platform: 'linux', env: { HOME: home }, homedir: home, documents: xdg, names: [previous] });
  assert.deepEqual(folders, [path.join(home, 'Documents', previous), path.join(xdg, previous)]);
  makeLegacy(path.join(xdg, previous));
  assert.deepEqual((await legacy.findLegacyFolders(folders, { target })).map((item) => item.folder), [path.join(xdg, previous)]);
});

test('finds a folder once when Documents is a link to the XDG folder', { skip: !posix }, async () => {
  const home = path.join(root, 'home', 'ben');
  const xdg = path.join(home, 'Dokumente');
  makeLegacy(path.join(xdg, previous));
  fs.symlinkSync(xdg, path.join(home, 'Documents'));
  const folders = legacy.candidateFolders({ platform: 'linux', env: { HOME: home }, homedir: home, documents: xdg, names: [previous] });
  assert.equal(folders.length, 2);
  assert.deepEqual((await legacy.findLegacyFolders(folders, { target })).map((item) => item.folder), [path.join(home, 'Documents', previous)]);
});

test('ignores homes that are not absolute and names that are not plain folder names', () => {
  const folders = legacy.candidateFolders({ platform: 'win32', env: { HOME: 'relativ', USERPROFILE: '' }, homedir: null, documents, names: [previous, '..', 'a/b', 'a\\b', 'C:', ' x', ''] });
  assert.deepEqual(folders, [path.join(documents, previous)]);
});

test('never takes a folder that holds the new profile or sits inside it', async () => {
  assert.deepEqual(await legacy.findLegacyFolders([folder], { target: path.join(folder, 'profile') }), []);
  assert.deepEqual(await legacy.findLegacyFolders([folder], { target: documents }), []);
});

test('copies data, keeps the old folder, restricts access and names what it left out', async () => {
  if (posix) fs.symlinkSync(os.tmpdir(), oldData('outside'));
  const result = await imported();
  assert.equal(result.outcome, 'imported');
  assert.equal(result.leftOut, 0);
  assert.equal(fs.readFileSync(newData(database), 'utf8'), 'db');
  assert.equal(fs.readFileSync(newData(GRADES), 'utf8'), fs.readFileSync(oldData(GRADES), 'utf8'));
  assert.equal(exists(newData('nested', 'school_tests.json')), true);
  assert.equal(exists(newData('outside')) || isLink(newData('outside')), false);
  assert.deepEqual(leftovers(), []);
  assert.equal(fs.readFileSync(oldData(database), 'utf8'), 'db');
  assert.equal(fs.readFileSync(oldData(legacy.KEY_FILE), 'utf8'), OLD_FILE_KEY);
  if (posix) {
    assert.ok(logs.some((line) => line.startsWith('left out links or special files') && line.includes('outside')));
    assert.equal(fs.statSync(newData(legacy.KEY_FILE)).mode & 0o777, 0o600);
    assert.equal(fs.statSync(newData(database)).mode & 0o777, 0o600);
    assert.equal(fs.statSync(newData()).mode & 0o777, 0o700);
    assert.equal(fs.statSync(newData('nested')).mode & 0o777, 0o700);
  }
});

test('carries the key the old app used into the key file, word for word', async () => {
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(keyFile(), KEY);
  assert.equal(fs.readdirSync(target).includes('.env'), false);
});

for (const [line, key] of [
  [`export SECRET_KEY="${KEY}" # Kommentar`, KEY],
  [`SECRET_KEY='${KEY}'`, KEY],
  [`SECRET_KEY = ${KEY}   `, KEY],
  ['SECRET_KEY=abc\\nzz0123456789abcdef0123456789abcdef', 'abc\\nzz0123456789abcdef0123456789abcdef'],
  [`SECRET_KEY="a b\\"c ${KEY}"`, `a b"c ${KEY}`],
  [`SECRET_KEY=${KEY}#kein Kommentar`, `${KEY}#kein Kommentar`],
  [`SECRET_KEY=${KEY} # siehe \${HOME}`, KEY],
  [`SECRET_KEY=\${nur_text_${KEY}`, `\${nur_text_${KEY}`],
]) {
  test(`reads an unusual key line the way the old app did: ${line}`, async () => {
    writeEnv(`${line}\r\n`);
    assert.equal(await outcome(), 'imported');
    assert.equal(keyFile(), key);
  });
}

test('reads each line on its own and skips a value it cannot finish', () => {
  const entries = legacy.readEnv('A="x" # Kommentar\nB=\'y\'\nC="unterminiert\nD=frei # Notiz\nE="a\\nb"\nF=a\\nb\nG="a\\\\"\nexport H\n');
  const value = (key) => (entries.has(key) ? entries.get(key).value : undefined);
  assert.equal(value('A'), 'x');
  assert.equal(value('B'), 'y');
  assert.equal(entries.has('C'), false);
  assert.equal(value('D'), 'frei');
  assert.equal(value('E'), 'a\nb');
  assert.equal(value('F'), 'a\\nb');
  assert.equal(entries.has('G'), false);
  assert.equal(value('H'), null);
});

test('stops on an unterminated key instead of guessing, and names the file', async () => {
  writeEnv(`SECRET_KEY="${KEY}\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear', reason: 'syntax', file: envFile() });
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('stops when a quote could be escaped the way python-dotenv reads it', async () => {
  writeEnv(`PFAD="C:\\\\Nutzer\\\\"\nSECRET_KEY=${KEY}\nNOTIZ="x"\n`);
  assert.equal(await outcome(), 'unclear');
  assert.equal(exists(newData()), false);
});

test('stops on unusual spaces that python-dotenv reads differently', async () => {
  writeEnv(`SECRET_KEY${NBSP}=${KEY}\n`);
  assert.equal(await outcome(), 'unclear');
  writeEnv(`# Hinweis${NBSP}mit Leerzeichen\nSECRET_KEY=${KEY}\n`);
  assert.equal(await outcome(), 'imported');
  assert.equal(keyFile(), KEY);
});

test('only doubts files that could hold the key', async () => {
  fs.rmSync(envFile());
  writeEnv('ZERTIFIKAT="-----BEGIN\nabc\n', '.env', documents);
  assert.equal((await imported()).key, 'kept');
  fs.rmSync(newData(), { recursive: true });
  writeEnv(`SECRET_KEY=${KEY}\n`);
  writeEnv(`SECRET_KEY="offen\n`, '.flaskenv');
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), KEY);
});

test('a later bare key line unsets the key, as in python-dotenv', async () => {
  writeEnv(`SECRET_KEY=${KEY}\nSECRET_KEY # später geleert\n`);
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

for (const line of ['SECRET_KEY=', 'SECRET_KEY=""', "export SECRET_KEY=''  # leer"]) {
  test(`an empty key means the key file, as in the old app: ${line}`, async () => {
    writeEnv(`${line}\n`);
    writeEnv(`SECRET_KEY=${OTHER_KEY}\n`, '.flaskenv');
    const result = await imported();
    assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
    assert.equal(keyFile(), OLD_FILE_KEY);
  });
}

test('an empty key in the environment means the key file, since Flask never replaced it', async () => {
  const result = await imported({ env: { SECRET_KEY: '' } });
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('stops on a settings file the old app could not have read', async () => {
  fs.writeFileSync(envFile(), Buffer.concat([Buffer.from('# Schl'), Buffer.from([0xfc]), Buffer.from(`ssel\nSECRET_KEY=${KEY}\n`)]));
  assert.deepEqual(await imported(), { outcome: 'unclear', reason: 'file', file: envFile() });
});

test('ignores the first line behind a byte order mark, as python-dotenv does', async () => {
  fs.writeFileSync(envFile(), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`SECRET_KEY=${KEY}\nGOOGLE_PROJECT_ID=projekt\n`)]));
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('stops when the first line behind a byte order mark leaves a quote open', async () => {
  fs.writeFileSync(envFile(), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`NOTIZ="offen\nSECRET_KEY=${KEY}\nENDE="x"\n`)]));
  assert.equal(await outcome(), 'unclear');
});

test('keeps an earlier key when a later duplicate cannot be read', async () => {
  writeEnv(`SECRET_KEY=${KEY}\nSECRET_KEY="x" kaputt\n`);
  assert.equal(await outcome(), 'imported');
  assert.equal(keyFile(), KEY);
});

for (const line of ['SECRET_KEY=${EINE_SEHR_LANGE_VARIABLE_FUER_DEN_SCHLUESSEL}', "SECRET_KEY='${FEHLT:-standard}_0123456789abcdef0123456789'"]) {
  test(`stops on a key that depends on another variable: ${line}`, async () => {
    writeEnv(`${line}\n`);
    assert.deepEqual(await imported(), { outcome: 'unclear', reason: 'variable', file: envFile() });
    assert.equal(exists(newData()), false);
  });
}

test('finds the settings the old app loaded above its folder, as Flask did', async () => {
  fs.rmSync(envFile());
  writeEnv(`SECRET_KEY=${OTHER_KEY}\n`, '.env', documents);
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), OTHER_KEY);
});

test('takes the key from .flaskenv when .env has none, and from .env when both have one', async () => {
  writeEnv('FLASK_ENV=development\n');
  writeEnv(`SECRET_KEY=${OTHER_KEY}\n`, '.flaskenv');
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), OTHER_KEY);
  fs.rmSync(newData(), { recursive: true });
  writeEnv(`SECRET_KEY=${KEY}\n`);
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), KEY);
});

test('stops when .env clears the key that .flaskenv sets, since Flask versions differ there', async () => {
  writeEnv('SECRET_KEY\n');
  writeEnv(`SECRET_KEY=${OTHER_KEY}\n`, '.flaskenv');
  assert.deepEqual(await imported(), { outcome: 'unclear', reason: 'syntax', file: envFile() });
});

test('carries a key from the environment when no file disagrees', async () => {
  fs.rmSync(envFile());
  fs.rmSync(oldData(legacy.KEY_FILE));
  const result = await imported({ env: { SECRET_KEY: OTHER_KEY } });
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(keyFile(), OTHER_KEY);
  fs.rmSync(newData(), { recursive: true });
  fs.writeFileSync(oldData(legacy.KEY_FILE), `${OTHER_KEY}\n`);
  assert.equal((await imported({ env: { SECRET_KEY: OTHER_KEY } })).key, 'carried');
});

test('stops when the environment and the files hold different keys for encrypted data', async () => {
  assert.deepEqual(await imported({ env: { SECRET_KEY: OTHER_KEY } }), { outcome: 'conflict', file: envFile() });
  fs.rmSync(envFile());
  assert.deepEqual(await imported({ env: { SECRET_KEY: OTHER_KEY } }), { outcome: 'conflict', file: oldData(legacy.KEY_FILE) });
});

test('on Windows, stops on another spelling of the key name', async () => {
  writeEnv(`secret_key=${OTHER_KEY}\nSECRET_KEY=${KEY}\n`);
  assert.deepEqual(await imported({ platform: 'win32' }), { outcome: 'unclear', reason: 'spelling', file: envFile() });
  assert.equal((await imported({ platform: 'linux' })).key, 'carried');
  assert.equal(keyFile(), KEY);
});

for (const rejected of ['your-secret-key-here', `${previous.toLowerCase()}-hub-secret-key-change-me`, 'CHANGEME', '  Please-Change-Me  ']) {
  test(`stops when data is encrypted with a rejected key: ${rejected}`, async () => {
    writeEnv(`SECRET_KEY="${rejected}"\n`);
    assert.deepEqual(await imported(), { outcome: 'weak', file: envFile() });
    assert.equal(exists(newData()), false);
  });

  test(`keeps the old key file when the old app used a rejected key but encrypted nothing: ${rejected}`, async () => {
    writeEnv(`SECRET_KEY="${rejected}"\n`);
    nothingEncrypted();
    const result = await imported();
    assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
    assert.equal(keyFile(), OLD_FILE_KEY);
  });
}

test('does not count caches as encrypted data', async () => {
  writeEnv('SECRET_KEY=your-secret-key-here\n');
  nothingEncrypted();
  fs.writeFileSync(oldData('weather_cache.json'), 'NEXUS2:wetter');
  fs.mkdirSync(oldData('vertretungsplan_cache'));
  fs.writeFileSync(oldData('vertretungsplan_cache', 'plan.meta'), 'ENC2:plan');
  assert.equal((await imported()).key, 'kept');
});

test('stops when a rejected key from the environment encrypted data', async () => {
  fs.rmSync(envFile());
  fs.rmSync(oldData(legacy.KEY_FILE));
  assert.deepEqual(await imported({ env: { SECRET_KEY: 'changeme' } }), { outcome: 'weak', file: null });
});

for (const [label, line] of [
  ['non-ASCII', `SECRET_KEY=Schlüssel-${KEY}`],
  ['a leading space', `SECRET_KEY=" ${KEY}"`],
  ['a trailing tab', `SECRET_KEY="${KEY}\\t"`],
]) {
  test(`stops on a key the key file cannot hold exactly: ${label}`, async () => {
    writeEnv(`${line}\n`);
    assert.deepEqual(await imported(), { outcome: 'unsupported', file: envFile() });
    assert.equal(exists(newData()), false);
    assert.deepEqual(leftovers(), []);
  });
}

test('follows a linked settings file, as python-dotenv did', { skip: !posix }, async () => {
  const real = path.join(root, 'echt.env');
  fs.writeFileSync(real, `SECRET_KEY=${OTHER_KEY}\n`);
  fs.rmSync(envFile());
  fs.symlinkSync(real, envFile());
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), OTHER_KEY);
});

test('uses the key file of the old data when there are no old settings', async () => {
  fs.rmSync(envFile());
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('writes the key file when only the old settings had a key', async () => {
  fs.rmSync(oldData(legacy.KEY_FILE));
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), KEY);
});

test('stops when encrypted data has no key at all, and starts without one when nothing is encrypted', async () => {
  fs.rmSync(oldData(legacy.KEY_FILE));
  fs.rmSync(envFile());
  assert.deepEqual(await imported(), { outcome: 'lost', file: oldData(legacy.KEY_FILE) });
  nothingEncrypted();
  assert.equal((await imported()).key, 'none');
  assert.equal(exists(newData(legacy.KEY_FILE)), false);
});

for (const [label, content] of [['empty', ''], ['short', 'kurz\n'], ['a placeholder', 'changeme'.padEnd(40, ' ')], ['shortened by its line breaks', `${'a\r\n'.repeat(11)}a`]]) {
  test(`drops a key file the backend would refuse, when nothing is encrypted with it: ${label}`, async () => {
    fs.rmSync(envFile());
    nothingEncrypted();
    fs.writeFileSync(oldData(legacy.KEY_FILE), content);
    const result = await imported();
    assert.deepEqual([result.outcome, result.key], ['imported', 'dropped']);
    assert.equal(exists(newData(legacy.KEY_FILE)), false);
    assert.equal(fs.readFileSync(oldData(legacy.KEY_FILE), 'utf8'), content);
  });
}

test('stops when data is encrypted with a key file the backend would refuse', async () => {
  fs.rmSync(envFile());
  fs.writeFileSync(oldData(legacy.KEY_FILE), 'kurz');
  assert.deepEqual(await imported(), { outcome: 'weak', file: oldData(legacy.KEY_FILE) });
});

test('keeps a key file with surrounding whitespace, and stops on one it cannot judge', async () => {
  fs.rmSync(envFile());
  fs.writeFileSync(oldData(legacy.KEY_FILE), `  ${OLD_FILE_KEY}\r\n`);
  assert.equal((await imported()).key, 'kept');
  fs.rmSync(newData(), { recursive: true });
  fs.writeFileSync(oldData(legacy.KEY_FILE), `Schlüssel-${OLD_FILE_KEY}`);
  assert.deepEqual(await imported(), { outcome: 'unsupported', file: oldData(legacy.KEY_FILE) });
});

test('stops on a key file that is a link', { skip: !posix }, async () => {
  fs.rmSync(envFile());
  const real = path.join(root, 'schluessel');
  fs.writeFileSync(real, OLD_FILE_KEY);
  fs.rmSync(oldData(legacy.KEY_FILE));
  fs.symlinkSync(real, oldData(legacy.KEY_FILE));
  assert.deepEqual(await imported(), { outcome: 'unclear', reason: 'file', file: oldData(legacy.KEY_FILE) });
});

test('does not stop for the key when nothing is encrypted with it', async () => {
  nothingEncrypted();
  writeEnv(`SECRET_KEY="${KEY}\n`);
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.ok(logs.some((line) => line.includes('nothing is encrypted with it')));
});

test('on request, takes over everything except the encrypted files and keeps the key file', async () => {
  writeEnv('SECRET_KEY=your-secret-key-here\n');
  fs.writeFileSync(oldData('weather_cache.json'), 'NEXUS2:wetter');
  fs.writeFileSync(oldData('.api_token'), 'ENC2:token');
  const result = await imported({ withoutEncrypted: true });
  assert.deepEqual([result.outcome, result.key, result.leftOut], ['imported', 'kept', 2]);
  assert.equal(exists(newData(GRADES)), false);
  assert.equal(exists(newData('weather_cache.json')), false);
  assert.equal(fs.readFileSync(newData('.api_token'), 'utf8'), 'ENC2:token');
  assert.equal(fs.readFileSync(newData(database), 'utf8'), 'db');
  assert.equal(keyFile(), OLD_FILE_KEY);
  assert.equal(exists(oldData(GRADES)), true);
  assert.ok(logs.some((line) => line.startsWith('left out encrypted files') && line.includes(GRADES)));
});

test('a readable key needs no request, and then nothing is left out', async () => {
  const result = await imported({ withoutEncrypted: true });
  assert.deepEqual([result.outcome, result.key, result.leftOut], ['imported', 'carried', 0]);
  assert.equal(exists(newData(GRADES)), true);
});

test('reports a failed copy and leaves nothing half done', { skip: !posix || process.getuid() === 0 }, async () => {
  const locked = oldData('nested', 'locked.json');
  fs.writeFileSync(locked, '{}');
  fs.chmodSync(locked, 0o000);
  const result = await imported();
  assert.deepEqual(result, { outcome: 'failed', code: 'EACCES' });
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
  assert.ok(logs.some((line) => line.includes('locked.json')));
});

test('cleans up when the last step fails', async () => {
  const result = await imported({ beforeMove: () => { throw Object.assign(new Error('weg'), { code: 'EIO' }); } });
  assert.deepEqual(result, { outcome: 'failed', code: 'EIO' });
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('replaces an empty data folder and skips one that filled up in the meantime', async () => {
  fs.mkdirSync(newData(), { recursive: true });
  assert.equal(await outcome(), 'imported');
  assert.equal(keyFile(), KEY);
  fs.rmSync(newData(), { recursive: true });
  const result = await imported({ beforeMove: (where) => fs.mkdirSync(path.join(where, 'data', 'neu'), { recursive: true }) });
  assert.deepEqual(result, { outcome: 'skipped' });
  assert.deepEqual(fs.readdirSync(newData()), ['neu']);
  assert.deepEqual(leftovers(), []);
});

test('waits while another program holds the port, before copying and before the last move', async () => {
  assert.deepEqual(await imported({ portFree: async () => false }), { outcome: 'busy' });
  assert.equal(exists(target) && fs.readdirSync(target).length > 0, false);
  let checks = 0;
  assert.deepEqual(await imported({ portFree: async () => (checks += 1) === 1 }), { outcome: 'busy' });
  assert.equal(checks, 2);
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('refuses to fill up the disk and names what it needs', async () => {
  const result = await imported({ freeSpace: async () => 1024 });
  assert.deepEqual(result, { outcome: 'space', needed: sizeOf(oldData()) + 64 * 1024 * 1024, free: 1024 });
  assert.equal(exists(newData()), false);
});

test('a profile the backend only set up counts as unused', async () => {
  unusedProfile();
  assert.equal(await legacy.dataState(newData()), 'unused');
  assert.equal(await legacy.isFresh(newData()), true);
  withDatabase(newData('hub.db'), (db) => db.exec("INSERT INTO hub_timetable_settings (tour_state, user_id) VALUES ('skipped', NULL)"));
  assert.equal(await legacy.dataState(newData()), 'unused');
  fs.rmSync(newData('hub.db'));
  assert.equal(await legacy.dataState(newData()), 'unused');
});

for (const [label, change] of [
  ['a saved setting', (db) => db.exec(`INSERT INTO ui_store VALUES ('app-theme-choice', '"dark"')`)],
  ['a task that was deleted again', (db) => db.exec("INSERT INTO hub_tasks (title) VALUES ('x'); DELETE FROM hub_tasks")],
  ['a changed theme next to the tour', (db) => db.exec("INSERT INTO hub_timetable_settings (tour_state, theme) VALUES ('skipped', 'light')")],
  ['two settings rows', (db) => db.exec("INSERT INTO hub_timetable_settings (tour_state) VALUES ('skipped'); INSERT INTO hub_timetable_settings (tour_state) VALUES ('done')")],
]) {
  test(`a profile with ${label} counts as used`, async () => {
    unusedProfile();
    withDatabase(newData('hub.db'), change);
    assert.equal(await legacy.dataState(newData()), 'used');
    assert.deepEqual(await imported(), { outcome: 'skipped' });
  });
}

for (const [label, change] of [
  ['any other file', () => fs.writeFileSync(newData('school_tests.json'), '[]')],
  ['a leftover journal', () => fs.writeFileSync(newData('hub.db-journal'), '')],
  ['a damaged database', () => fs.writeFileSync(newData('hub.db'), 'kaputt')],
  ['a folder', () => fs.mkdirSync(newData('models'))],
]) {
  test(`a profile with ${label} counts as used`, async () => {
    unusedProfile();
    change();
    assert.equal(await legacy.dataState(newData()), 'used');
    assert.deepEqual(await imported(), { outcome: 'skipped' });
  });
}

test('replaces a profile nobody used and keeps nothing of it', async () => {
  unusedProfile();
  const result = await imported();
  assert.deepEqual([result.outcome, result.key, result.replaced], ['imported', 'carried', true]);
  assert.equal(keyFile(), KEY);
  assert.equal(exists(newData('.api_token')), false);
  assert.equal(exists(newData('hub.db')), false);
  assert.equal(fs.readFileSync(newData(database), 'utf8'), 'db');
  assert.deepEqual(leftovers(), []);
});

test('puts a profile nobody used back when the last move fails', async () => {
  unusedProfile();
  const before = snapshot(newData());
  let moves = 0;
  const move = async (from, to) => {
    moves += 1;
    if (moves === 2) throw Object.assign(new Error('gesperrt'), { code: 'EBUSY' });
    await retryingRename(from, to);
  };
  assert.deepEqual(await imported({ move }), { outcome: 'failed', code: 'EBUSY' });
  assert.equal(moves, 3);
  assert.deepEqual(snapshot(newData()), before);
  assert.deepEqual(leftovers(), []);
});

test('skips a profile that got used while copying', async () => {
  unusedProfile();
  const beforeMove = () => withDatabase(newData('hub.db'), (db) => db.exec("INSERT INTO hub_tasks (title) VALUES ('neu')"));
  assert.deepEqual(await imported({ beforeMove }), { outcome: 'skipped' });
  assert.equal(keyFile(), 'a'.repeat(64));
  assert.deepEqual(leftovers(), []);
});

test('only clears leftovers it made itself', async () => {
  const ours = (name) => {
    fs.mkdirSync(path.join(target, name), { recursive: true });
    fs.writeFileSync(path.join(target, name, '.import-work'), '');
  };
  fs.mkdirSync(path.join(target, '.data-import-notizen'), { recursive: true });
  fs.mkdirSync(path.join(target, '.data-import-backup'), { recursive: true });
  fs.mkdirSync(path.join(target, '.data-import-Xy12ab'), { recursive: true });
  ours('.data-import-AbC123');
  await legacy.cleanUp(target);
  assert.equal(exists(path.join(target, '.data-import-notizen')), true);
  assert.equal(exists(path.join(target, '.data-import-backup')), true);
  assert.equal(exists(path.join(target, '.data-import-Xy12ab')), true);
  assert.equal(exists(path.join(target, '.data-import-AbC123')), false);
});

test('never follows a staging link that someone left behind', { skip: !posix }, async () => {
  fs.mkdirSync(target, { recursive: true });
  const guard = path.join(root, 'guard');
  fs.mkdirSync(guard);
  fs.writeFileSync(path.join(guard, 'keep.txt'), 'keep');
  fs.writeFileSync(path.join(guard, '.import-work'), '');
  fs.symlinkSync(guard, path.join(target, '.data-import-Link12'));
  assert.equal(await outcome(), 'imported');
  assert.deepEqual(fs.readdirSync(guard).sort(), ['.import-work', 'keep.txt']);
  assert.equal(isLink(path.join(target, '.data-import-Link12')), true);
});

test('shares its key rules with the backend', () => {
  const source = fs.readFileSync(path.join(repository, 'app', 'crypto_utils.py'), 'utf8');
  const minimum = Number(/^_MIN_SECRET_LENGTH = (\d+)$/m.exec(source)[1]);
  const block = /_PLACEHOLDER_SECRETS = \{([^}]*)\}/.exec(source)[1];
  const placeholders = [...block.matchAll(/'([^']*)'/g)].map((match) => match[1]).sort();
  assert.equal(legacy.MINIMUM_SECRET_LENGTH, minimum);
  assert.deepEqual([...legacy.PLACEHOLDER_SECRETS].sort(), placeholders);
  assert.match(source, /key_file\.read_text\(\)\.strip\(\)/);
  assert.match(source, /_SALT_PREFIX = 'ENC2:'/);
  assert.match(source, /_LEGACY_SALT_PREFIX = '\w+2:'/);
});

test('without python-dotenv it stops on a file its own reader might misread', async () => {
  writeEnv(`GOOGLE_CLIENT_SECRET="abc\nSECRET_KEY=${KEY}\nFOO="x"\n`);
  assert.equal(await outcome(), 'unclear');
  writeEnv(`'SECRET_KEY'=${KEY}\n`);
  assert.equal(await outcome(), 'unclear');
});

test('a failing Python lookup only means reading without Python', async () => {
  const result = await imported({ python: async () => { throw Object.assign(new Error('spawn EINVAL'), { code: 'EINVAL' }); } });
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.ok(logs.some((line) => line.includes('without Python')));
});

test('does not look for Python when there are no settings files at all', { skip: !posix }, async () => {
  fs.rmSync(envFile());
  fs.rmSync(path.join(root, '.env'));
  fs.rmSync(path.join(root, '.flaskenv'));
  let asked = false;
  await imported({ python: async () => { asked = true; return null; } });
  assert.equal(asked, false);
});

test('stops a hanging interpreter instead of waiting for it', { skip: !posix }, async () => {
  const fake = path.join(root, 'haengt');
  fs.writeFileSync(fake, `#!/bin/sh\necho $$ > "${root}/pid"\nexec sleep 30\n`, { mode: 0o755 });
  const started = Date.now();
  assert.equal(await legacy.pythonDotenvKey(fake, folder, { timeout: 1000 }), undefined);
  assert.ok(Date.now() - started < 10000);
  const pid = Number(fs.readFileSync(path.join(root, 'pid'), 'utf8'));
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.throws(() => process.kill(pid, 0));
});

test('with python-dotenv: carries a plain key and checks it', { skip: noPython }, async () => {
  const result = await checked();
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(keyFile(), KEY);
  assert.ok(logs.some((line) => line.startsWith('checked ')));
});

test('with python-dotenv: takes nothing that an open quote swallowed', { skip: noPython }, async () => {
  writeEnv(`GOOGLE_CLIENT_SECRET="abc\nSECRET_KEY=${KEY}\nFOO="x"\n`);
  const result = await checked();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('with python-dotenv: takes nothing behind an escaped closing quote', { skip: noPython }, async () => {
  writeEnv(`PFAD="C:\\\\Nutzer\\\\"\nSECRET_KEY=${KEY}\nNOTIZ="x"\n`);
  assert.equal((await checked()).key, 'kept');
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('with python-dotenv: an empty key means the key file', { skip: noPython }, async () => {
  writeEnv('SECRET_KEY=""\n');
  assert.equal((await checked()).key, 'kept');
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('with python-dotenv: stops when the key spans two lines', { skip: noPython }, async () => {
  writeEnv(`SECRET_KEY="${KEY}\n"\n`);
  assert.equal((await checked()).outcome, 'unclear');
  assert.equal(exists(newData()), false);
});

test('with python-dotenv: stops when the key name itself is quoted', { skip: noPython }, async () => {
  writeEnv(`'SECRET_KEY'=${KEY}\n`);
  assert.equal((await checked()).outcome, 'unclear');
});

test('with python-dotenv: ignores Python files next to the old install', { skip: noPython }, async () => {
  fs.writeFileSync(path.join(folder, 'json.py'), "open('untergeschoben', 'w').write('1')\nraise SystemExit(3)\n");
  fs.writeFileSync(path.join(folder, 'dotenv.py'), "open('untergeschoben', 'w').write('1')\nraise SystemExit(3)\n");
  const result = await checked();
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(exists(path.join(folder, 'untergeschoben')), false);
  assert.equal(keyFile(), KEY);
});

test('with python-dotenv: stops on a key that comes from another variable', { skip: noPython }, async () => {
  writeEnv(`TEIL=${KEY}\nSECRET_KEY=\${TEIL}\n`);
  assert.deepEqual(await checked(), { outcome: 'unclear', reason: 'variable', file: envFile() });
});

test('with python-dotenv: follows the settings Flask loaded above the folder and from .flaskenv', { skip: noPython }, async () => {
  fs.rmSync(envFile());
  writeEnv(`SECRET_KEY=${OTHER_KEY}\n`, '.env', documents);
  assert.equal((await checked()).key, 'carried');
  assert.equal(keyFile(), OTHER_KEY);
  fs.rmSync(newData(), { recursive: true });
  writeEnv('FLASK_ENV=development\n');
  writeEnv(`SECRET_KEY=${KEY}\n`, '.flaskenv');
  assert.equal((await checked()).key, 'carried');
  assert.equal(keyFile(), KEY);
});

test('with python-dotenv: writes nothing into the old folder', { skip: noPython }, async () => {
  const before = snapshot(folder);
  assert.equal((await checked()).outcome, 'imported');
  assert.deepEqual(snapshot(folder), before);
});

test('the backend reads the carried key and the kept key file as the old app did', { skip: backendPython ? false : 'Python mit cryptography fehlt' }, async () => {
  const backendKey = () => {
    const env = { ...process.env, HUB_DATA_DIR: newData() };
    delete env.SECRET_KEY;
    const run = spawnSync(backendPython, ['-c', 'from app.crypto_utils import _get_secret_key; print(_get_secret_key())'], { cwd: repository, env, encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    return run.stdout.trim();
  };
  writeEnv(`export SECRET_KEY="${KEY} mit Leerzeichen"\n`);
  assert.equal((await imported()).key, 'carried');
  assert.equal(backendKey(), `${KEY} mit Leerzeichen`);
  fs.rmSync(newData(), { recursive: true });
  fs.rmSync(envFile());
  fs.writeFileSync(oldData(legacy.KEY_FILE), `${OLD_FILE_KEY}\n`);
  assert.equal((await imported()).key, 'kept');
  assert.equal(backendKey(), OLD_FILE_KEY);
});
