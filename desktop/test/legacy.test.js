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
const OLD_FILE_KEY = 'f'.repeat(64);
const [previous] = brand.previousNames;
const database = `${previous.toLowerCase()}.db`;
const prefix = previous.toUpperCase().replace(/[^A-Z0-9]+/g, '_');
const posix = process.platform !== 'win32';
const repository = path.resolve(__dirname, '..', '..');

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

test.beforeEach(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'legacy-import-'));
  documents = path.join(root, 'Documents');
  folder = path.join(documents, previous);
  target = path.join(root, 'profile');
  fs.mkdirSync(path.join(folder, 'data', 'nested'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'data', database), 'db');
  fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), OLD_FILE_KEY);
  fs.writeFileSync(path.join(folder, 'data', 'nested', 'school_tests.json'), '[]');
  writeEnv(`FLASK_ENV=development\nSECRET_KEY=${KEY}\n${prefix}_DATA_DIR=/woanders\n${prefix}_PORT=6060\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n`);
});

test.afterEach(() => {
  if (posix) spawnSync('chmod', ['-R', 'u+rwX', root]);
  fs.rmSync(root, { recursive: true, force: true });
});

function writeEnv(text) {
  fs.writeFileSync(path.join(folder, '.env'), text);
}

const imported = (options = {}) => legacy.importLegacyData({ legacy: folder, target, ...options });
const checked = (options = {}) => imported({ python, ...options });
const newData = (...parts) => path.join(target, 'data', ...parts);
const keyFile = () => fs.readFileSync(newData(legacy.KEY_FILE), 'utf8');
const exists = (file) => fs.existsSync(file);
const leftovers = () => (exists(target) ? fs.readdirSync(target).filter((name) => name.startsWith('.data-import-')) : []);
const find = (options = {}) => legacy.findLegacyFolders(legacy.candidateFolders({ documents, names: [previous], ...options }), { target });

function makeLegacy(where, content = 'db') {
  fs.mkdirSync(path.join(where, 'data'), { recursive: true });
  fs.writeFileSync(path.join(where, 'data', database), content);
}

test('finds the old folder while the new data folder is missing or empty', async () => {
  assert.deepEqual((await find()).map((item) => item.folder), [folder]);
  assert.equal(await legacy.isFresh(newData()), true);
  fs.mkdirSync(newData(), { recursive: true });
  assert.equal(await legacy.isFresh(newData()), true);
});

test('leaves a new data folder with content alone', async () => {
  fs.mkdirSync(newData(), { recursive: true });
  fs.writeFileSync(newData('hub.db'), 'neu');
  assert.equal(await legacy.isFresh(newData()), false);
  assert.deepEqual(await imported(), { outcome: 'skipped' });
  assert.equal(fs.readFileSync(newData('hub.db'), 'utf8'), 'neu');
});

test('treats a data path that is a file or a link as used', { skip: !posix }, async () => {
  fs.mkdirSync(target, { recursive: true });
  fs.symlinkSync(root, newData());
  assert.equal(await legacy.isFresh(newData()), false);
  fs.unlinkSync(newData());
  fs.writeFileSync(newData(), '');
  assert.equal(await legacy.isFresh(newData()), false);
});

test('ignores an old folder without data', async () => {
  fs.rmSync(path.join(folder, 'data'), { recursive: true });
  fs.mkdirSync(path.join(folder, 'data'));
  assert.deepEqual(await find(), []);
});

test('ignores an old folder or data folder that is only a link', { skip: !posix }, async () => {
  const real = path.join(root, 'elsewhere');
  fs.mkdirSync(real);
  fs.renameSync(folder, path.join(real, previous));
  fs.symlinkSync(path.join(real, previous), folder);
  assert.deepEqual(await find(), []);
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

test('copies data, keeps the old folder and restricts access', async () => {
  if (posix) fs.symlinkSync(os.tmpdir(), path.join(folder, 'data', 'outside'));
  const result = await imported();
  assert.equal(result.outcome, 'imported');
  assert.equal(fs.readFileSync(newData(database), 'utf8'), 'db');
  assert.equal(exists(newData('nested', 'school_tests.json')), true);
  assert.equal(fs.existsSync(newData('outside')) || isLink(newData('outside')), false);
  assert.deepEqual(leftovers(), []);
  assert.equal(fs.readFileSync(path.join(folder, 'data', database), 'utf8'), 'db');
  assert.equal(fs.readFileSync(path.join(folder, 'data', legacy.KEY_FILE), 'utf8'), OLD_FILE_KEY);
  if (posix) {
    assert.equal(fs.statSync(newData(legacy.KEY_FILE)).mode & 0o777, 0o600);
    assert.equal(fs.statSync(newData(database)).mode & 0o777, 0o600);
    assert.equal(fs.statSync(newData()).mode & 0o777, 0o700);
    assert.equal(fs.statSync(newData('nested')).mode & 0o777, 0o700);
  }
});

function isLink(file) {
  try {
    return fs.lstatSync(file).isSymbolicLink();
  } catch {
    return false;
  }
}

test('carries the key from the old settings into the key file, word for word', async () => {
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
]) {
  test(`reads an unusual key line the way the old app did: ${line}`, async () => {
    writeEnv(`${line}\r\n`);
    assert.equal((await imported()).outcome, 'imported');
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

test('stops on an unterminated key instead of guessing', async () => {
  writeEnv(`SECRET_KEY="${KEY}\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear' });
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('stops when a quote could be escaped the way python-dotenv reads it', async () => {
  writeEnv(`PFAD="C:\\\\Nutzer\\\\"\nSECRET_KEY=${KEY}\nNOTIZ="x"\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear' });
  assert.equal(exists(newData()), false);
});

test('stops on unusual spaces that python-dotenv reads differently', async () => {
  writeEnv(`SECRET_KEY\u00a0=${KEY}\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear' });
  writeEnv(`# Hinweis\u00a0mit Leerzeichen\nSECRET_KEY=${KEY}\n`);
  assert.equal((await imported()).outcome, 'imported');
  assert.equal(keyFile(), KEY);
});

test('a later bare key line unsets the key, as in python-dotenv', async () => {
  writeEnv(`SECRET_KEY=${KEY}\nSECRET_KEY # später geleert\n`);
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('takes nothing from an old environment file python-dotenv could not read', async () => {
  fs.writeFileSync(path.join(folder, '.env'), Buffer.concat([Buffer.from('# Schl'), Buffer.from([0xfc]), Buffer.from(`ssel\nSECRET_KEY=${KEY}\n`)]));
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('ignores the first line behind a byte order mark, as python-dotenv does', async () => {
  fs.writeFileSync(path.join(folder, '.env'), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`SECRET_KEY=${KEY}\nGOOGLE_PROJECT_ID=projekt\n`)]));
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('stops when the first line behind a byte order mark leaves a quote open', async () => {
  fs.writeFileSync(path.join(folder, '.env'), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`NOTIZ="offen\nSECRET_KEY=${KEY}\nENDE="x"\n`)]));
  assert.deepEqual(await imported(), { outcome: 'unclear' });
});

test('keeps an earlier key when a later duplicate cannot be read', async () => {
  writeEnv(`SECRET_KEY=${KEY}\nSECRET_KEY="x" kaputt\n`);
  assert.equal((await imported()).outcome, 'imported');
  assert.equal(keyFile(), KEY);
});

test('leaves a key behind that depends on another variable', async () => {
  writeEnv('SECRET_KEY=${EINE_SEHR_LANGE_VARIABLE_FUER_DEN_SCHLUESSEL}\n');
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('leaves a key behind that would be expanded even in single quotes', async () => {
  writeEnv("SECRET_KEY='${FEHLT}_0123456789abcdef0123456789'\n");
  assert.equal((await imported()).key, 'kept');
  assert.equal(keyFile(), OLD_FILE_KEY);
});

for (const rejected of ['your-secret-key-here', `${previous.toLowerCase()}-hub-secret-key-change-me`, 'CHANGEME', '  Please-Change-Me  ']) {
  test(`leaves a key behind that the backend would reject: ${rejected}`, async () => {
    writeEnv(`SECRET_KEY="${rejected}"\n`);
    const result = await imported();
    assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
    assert.equal(keyFile(), OLD_FILE_KEY);
  });
}

for (const [label, line] of [
  ['non-ASCII', `SECRET_KEY=Schlüssel-${KEY}`],
  ['a leading space', `SECRET_KEY=" ${KEY}"`],
  ['a trailing tab', `SECRET_KEY="${KEY}\\t"`],
]) {
  test(`stops on a key the key file cannot hold exactly: ${label}`, async () => {
    writeEnv(`${line}\n`);
    assert.deepEqual(await imported(), { outcome: 'unsupported' });
    assert.equal(exists(newData()), false);
    assert.deepEqual(leftovers(), []);
  });
}

test('stops on an environment file that is not a plain file', { skip: !posix }, async () => {
  const real = path.join(root, 'echt.env');
  fs.writeFileSync(real, `SECRET_KEY=${KEY}\n`);
  fs.rmSync(path.join(folder, '.env'));
  fs.symlinkSync(real, path.join(folder, '.env'));
  assert.deepEqual(await imported(), { outcome: 'unclear' });
});

test('uses the key file of the old data when there are no old settings', async () => {
  fs.rmSync(path.join(folder, '.env'));
  const result = await imported();
  assert.deepEqual([result.outcome, result.key], ['imported', 'kept']);
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('writes the key file when only the old settings had a key', async () => {
  fs.rmSync(path.join(folder, 'data', legacy.KEY_FILE));
  assert.equal((await imported()).key, 'carried');
  assert.equal(keyFile(), KEY);
});

test('starts without a key file when there is no key at all', async () => {
  fs.rmSync(path.join(folder, 'data', legacy.KEY_FILE));
  fs.rmSync(path.join(folder, '.env'));
  assert.equal((await imported()).key, 'none');
  assert.equal(exists(newData(legacy.KEY_FILE)), false);
});

for (const [label, content] of [['empty', ''], ['short', 'kurz\n'], ['a placeholder', 'changeme'.padEnd(40, ' ')]]) {
  test(`drops a key file the backend would refuse to start with: ${label}`, async () => {
    fs.rmSync(path.join(folder, '.env'));
    fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), content);
    const result = await imported();
    assert.deepEqual([result.outcome, result.key], ['imported', 'dropped']);
    assert.equal(exists(newData(legacy.KEY_FILE)), false);
    assert.equal(fs.readFileSync(path.join(folder, 'data', legacy.KEY_FILE), 'utf8'), content);
  });
}

test('keeps a key file with surrounding whitespace or characters it cannot judge', async () => {
  fs.rmSync(path.join(folder, '.env'));
  fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), `  ${OLD_FILE_KEY}\n`);
  assert.equal((await imported()).key, 'kept');
  fs.rmSync(newData(), { recursive: true });
  fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), 'Schlüssel');
  assert.equal((await imported()).key, 'kept');
  assert.equal(keyFile(), 'Schlüssel');
});

test('reports a failed copy and leaves nothing half done', { skip: !posix || process.getuid() === 0 }, async () => {
  const locked = path.join(folder, 'data', 'nested', 'locked.json');
  fs.writeFileSync(locked, '{}');
  fs.chmodSync(locked, 0o000);
  const result = await imported();
  assert.equal(result.outcome, 'failed');
  assert.equal(result.code, 'EACCES');
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('cleans up when the last step fails', async () => {
  const result = await imported({ beforeMove: () => { throw Object.assign(new Error('weg'), { code: 'EIO' }); } });
  assert.deepEqual(result, { outcome: 'failed', code: 'EIO' });
  assert.equal(exists(newData()), false);
  assert.deepEqual(leftovers(), []);
});

test('replaces an empty data folder and skips one that filled up in the meantime', async () => {
  fs.mkdirSync(newData(), { recursive: true });
  assert.equal((await imported()).outcome, 'imported');
  assert.equal(keyFile(), KEY);
  fs.rmSync(newData(), { recursive: true });
  const result = await imported({ beforeMove: (where) => fs.mkdirSync(path.join(where, 'data', 'neu'), { recursive: true }) });
  assert.deepEqual(result, { outcome: 'skipped' });
  assert.deepEqual(fs.readdirSync(newData()), ['neu']);
  assert.deepEqual(leftovers(), []);
});

test('refuses to fill up the disk', async () => {
  const result = await imported({ freeSpace: async () => 1024 });
  assert.equal(result.outcome, 'space');
  assert.equal(result.free, 1024);
  assert.equal(result.needed, 2 + 64 + 2);
  assert.equal(exists(newData()), false);
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
  assert.equal((await imported()).outcome, 'imported');
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
});

test('without python-dotenv it stops on a file its own reader might misread', async () => {
  writeEnv(`GOOGLE_CLIENT_SECRET="abc\nSECRET_KEY=${KEY}\nFOO="x"\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear' });
  writeEnv(`'SECRET_KEY'=${KEY}\n`);
  assert.deepEqual(await imported(), { outcome: 'unclear' });
});

test('stops a hanging interpreter instead of waiting for it', { skip: !posix }, async () => {
  const fake = path.join(root, 'haengt');
  fs.writeFileSync(fake, `#!/bin/sh\necho $$ > "${root}/pid"\nexec sleep 30\n`, { mode: 0o755 });
  const started = Date.now();
  assert.equal(await legacy.dotenvValues(fake, path.join(folder, '.env'), { cwd: folder, timeout: 1000 }), null);
  assert.ok(Date.now() - started < 10000);
  const pid = Number(fs.readFileSync(path.join(root, 'pid'), 'utf8'));
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.throws(() => process.kill(pid, 0));
});

test('with python-dotenv: carries a plain key and checks it', { skip: noPython }, async () => {
  const result = await checked();
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(keyFile(), KEY);
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

test('with python-dotenv: stops when the key spans two lines', { skip: noPython }, async () => {
  writeEnv(`SECRET_KEY="${KEY}\n"\n`);
  assert.deepEqual(await checked(), { outcome: 'unclear' });
  assert.equal(exists(newData()), false);
});

test('with python-dotenv: stops when the key name itself is quoted', { skip: noPython }, async () => {
  writeEnv(`'SECRET_KEY'=${KEY}\n`);
  assert.deepEqual(await checked(), { outcome: 'unclear' });
});

test('with python-dotenv: ignores Python files next to the old install', { skip: noPython }, async () => {
  fs.writeFileSync(path.join(folder, 'json.py'), "open('untergeschoben', 'w').write('1')\nraise SystemExit(3)\n");
  const result = await checked();
  assert.deepEqual([result.outcome, result.key], ['imported', 'carried']);
  assert.equal(exists(path.join(folder, 'untergeschoben')), false);
  assert.equal(keyFile(), KEY);
});

test('with python-dotenv: leaves a key behind that comes from another variable', { skip: noPython }, async () => {
  writeEnv(`TEIL=${KEY}\nSECRET_KEY=\${TEIL}\n`);
  assert.equal((await checked()).key, 'kept');
  assert.equal(keyFile(), OLD_FILE_KEY);
});

test('with python-dotenv: writes nothing into the old folder', { skip: noPython }, async () => {
  const before = snapshot(folder);
  assert.equal((await checked()).outcome, 'imported');
  assert.deepEqual(snapshot(folder), before);
});

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
  fs.rmSync(path.join(folder, '.env'));
  fs.writeFileSync(path.join(folder, 'data', legacy.KEY_FILE), `${OLD_FILE_KEY}\n`);
  assert.equal((await imported()).key, 'kept');
  assert.equal(backendKey(), OLD_FILE_KEY);
});
