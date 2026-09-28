// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { execFile } = require('child_process');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');

const KEY_NAME = 'SECRET_KEY';
const KEY_FILE = '.secret_key';
const TOKEN_FILE = '.api_token';
const DATABASE_FILE = 'hub.db';
const GENERATED_FILES = new Set([KEY_FILE, TOKEN_FILE, DATABASE_FILE]);
const SETTINGS_FILES = ['.flaskenv', '.env'];
const ENCRYPTED_PREFIXES = ['ENC2:', 'NEXUS2:', 'gAAAAA'].map((prefix) => Buffer.from(prefix));
const MARKER = '.import-work';
const WORK_PREFIX = '.data-import-';
const WORK_NAME = /^\.data-import-[A-Za-z0-9]{6}$/;
const MINIMUM_SECRET_LENGTH = 32;
const PLACEHOLDER_SECRETS = new Set(['your-secret-key-here', 'secret-key-change-me', 'changeme', 'please-change-me']);
const SETTINGS_LIMIT = 1024 * 1024;
const SPACE_RESERVE = 64 * 1024 * 1024;
const RETRIES = 8;
const RETRIED_ERRORS = new Set(['EPERM', 'EACCES', 'EBUSY']);

const DOTENV_SCRIPT = [
  'import json',
  'import os',
  'import dotenv',
  'try:',
  '    from flask.cli import load_dotenv',
  'except ImportError:',
  '    def load_dotenv():',
  '        data = {}',
  "        for name in ('.flaskenv', '.env'):",
  '            found = dotenv.find_dotenv(name, usecwd=True)',
  '            if found:',
  "                data.update(dotenv.dotenv_values(found, encoding='utf-8'))",
  '        for key, value in data.items():',
  '            if key not in os.environ and value is not None:',
  '                os.environ[key] = value',
  'load_dotenv()',
  "print(json.dumps(os.environ.get('SECRET_KEY')))",
  '',
].join('\n');

const ASSIGNMENT = /^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*=[ \t]*(.*)$/;
const BARE_KEY = /^[ \t]*(?:export[ \t]+)?([^=#\s]+)[ \t]*(?:#.*)?$/;
const ANY_ASSIGNMENT = /^[ \t]*(?:export[ \t]+)?[^=#\s]+[ \t]*=[ \t]*(.*)$/;
const QUOTED_KEY = /^[ \t]*(?:export[ \t]+)?['"]/;
const TRAILER = /^[ \t]*(?:#.*)?$/;
const INTERPOLATION = /\$\{[^}:]*(?::-[^}]*)?\}/;
const UNUSUAL_SPACES = new Set([0x0b, 0x0c, 0x1c, 0x1d, 0x1e, 0x1f, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff]);
const BOM = String.fromCharCode(0xfeff);
const KEY_FILE_SAFE = /^[\x21-\x7e](?:[\x20-\x7e]*[\x21-\x7e])?$/;
const PYTHON_SPACE = ' \t\n\r\x0b\x0c\x1c\x1d\x1e\x1f';
const DOUBLE_ESCAPES = { '\\': '\\', "'": "'", '"': '"', a: '\x07', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t', v: '\v' };
const SINGLE_ESCAPES = { '\\': '\\', "'": "'" };

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const quiet = () => {};

function absolute(value) {
  return typeof value === 'string' && value !== '' && path.isAbsolute(value);
}

function plainName(name) {
  return typeof name === 'string' && name !== '' && name === name.trim() && name !== '.' && name !== '..' && !/[\\/:]/.test(name);
}

function candidateFolders({ platform = process.platform, env = {}, homedir = null, documents = null, names = [] }) {
  const homes = platform === 'win32' ? [env.HOME, env.USERPROFILE, homedir] : [env.HOME, homedir];
  const roots = homes.filter(absolute).map((home) => path.join(path.resolve(home), 'Documents'));
  if (absolute(documents)) roots.push(path.resolve(documents));
  const seen = new Set();
  const folders = [];
  for (const root of roots) {
    for (const name of names.filter(plainName)) {
      const folder = path.join(root, name);
      const key = platform === 'win32' ? folder.toLowerCase() : folder;
      if (seen.has(key)) continue;
      seen.add(key);
      folders.push(folder);
    }
  }
  return folders;
}

async function lstatOrNull(target) {
  try {
    return await fsp.lstat(target);
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return null;
    throw error;
  }
}

async function kindOf(target) {
  try {
    const info = await fsp.lstat(target);
    if (info.isSymbolicLink()) return 'link';
    if (info.isDirectory()) return 'directory';
    return info.isFile() ? 'file' : 'other';
  } catch (error) {
    return error.code === 'ENOENT' || error.code === 'ENOTDIR' ? 'missing' : `unreadable (${error.code || error.message})`;
  }
}

async function identity(target) {
  let current = path.resolve(target);
  const missing = [];
  let resolved = null;
  while (resolved === null) {
    try {
      resolved = path.join(await fsp.realpath(current), ...missing.reverse());
    } catch {
      const parent = path.dirname(current);
      if (parent === current) {
        resolved = path.resolve(target);
      } else {
        missing.push(path.basename(current));
        current = parent;
      }
    }
  }
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

function contains(parent, child) {
  const relative = path.relative(parent, child);
  return relative === '' || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

async function walkFiles(dir, visit) {
  for (const name of await fsp.readdir(dir)) {
    const item = path.join(dir, name);
    const info = await fsp.lstat(item);
    if (info.isDirectory()) {
      if (await walkFiles(item, visit)) return true;
    } else if (await visit(item, info)) {
      return true;
    }
  }
  return false;
}

async function measure(dir) {
  const total = { files: 0, bytes: 0, newest: null };
  await walkFiles(dir, (_item, info) => {
    if (info.isFile()) {
      total.files += 1;
      total.bytes += info.size;
      total.newest = Math.max(total.newest || 0, info.mtimeMs);
    }
    return false;
  });
  return total;
}

async function findLegacyFolders(folders, { target, log = quiet }) {
  const targetIdentity = await identity(target);
  const seen = new Set();
  const found = [];
  for (const folder of folders) {
    const data = path.join(folder, 'data');
    const kinds = [await kindOf(folder), await kindOf(data)];
    if (kinds[0] === 'missing') continue;
    if (kinds[0] !== 'directory' || kinds[1] !== 'directory') {
      if (kinds[1] !== 'missing') log(`not offering ${folder}: the folder is ${kinds[0]}, its data folder is ${kinds[1]}`);
      continue;
    }
    const name = path.basename(folder);
    const databases = [await kindOf(path.join(data, `${name.toLowerCase()}.db`)), await kindOf(path.join(data, DATABASE_FILE))];
    if (!databases.includes('file')) {
      log(`not offering ${folder}: its data folder holds no database`);
      continue;
    }
    const id = await identity(folder);
    if (seen.has(id) || contains(id, targetIdentity) || contains(targetIdentity, id)) continue;
    seen.add(id);
    const size = await measure(data).catch((error) => {
      log(`could not measure ${data}:`, error.code || error.message);
      return { files: null, bytes: null, newest: null };
    });
    found.push({ folder, name, ...size });
  }
  return found;
}

function databaseIsEmpty(file) {
  let database = null;
  try {
    const { DatabaseSync } = require('node:sqlite');
    database = new DatabaseSync(file, { readOnly: true });
    const tables = database.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all();
    return tables.every(({ name }) => !database.prepare(`SELECT 1 FROM "${String(name).replace(/"/g, '""')}" LIMIT 1`).get());
  } catch {
    return false;
  } finally {
    try {
      if (database) database.close();
    } catch {}
  }
}

async function dataState(dir) {
  const info = await lstatOrNull(dir);
  if (!info) return 'missing';
  if (!info.isDirectory()) return 'used';
  const names = await fsp.readdir(dir);
  if (!names.length) return 'empty';
  for (const name of names) {
    if (!GENERATED_FILES.has(name) || !(await fsp.lstat(path.join(dir, name))).isFile()) return 'used';
  }
  return !names.includes(DATABASE_FILE) || databaseIsEmpty(path.join(dir, DATABASE_FILE)) ? 'unused' : 'used';
}

async function isFresh(dir) {
  try {
    return (await dataState(dir)) !== 'used';
  } catch {
    return false;
  }
}

function lines(text) {
  return text.split(/\r\n|\r|\n/);
}

function closingQuote(raw) {
  for (let index = 1; index < raw.length; index += 1) {
    if (raw[index] === raw[0] && raw[index - 1] !== '\\') return index;
  }
  return -1;
}

function unterminated(raw) {
  return (raw[0] === '"' || raw[0] === "'") && closingQuote(raw) < 0;
}

function parseValue(raw) {
  const quote = raw[0];
  if (quote !== '"' && quote !== "'") return raw.replace(/\s+#.*$/, '').trimEnd();
  const end = closingQuote(raw);
  if (end < 0 || !TRAILER.test(raw.slice(end + 1))) return null;
  const escapes = quote === '"' ? DOUBLE_ESCAPES : SINGLE_ESCAPES;
  const pattern = quote === '"' ? /\\[\\'"abfnrtv]/g : /\\[\\']/g;
  return raw.slice(1, end).replace(pattern, (match) => escapes[match[1]]);
}

function readEnv(text) {
  const entries = new Map();
  const all = lines(text);
  for (let index = text.startsWith(BOM) ? 1 : 0; index < all.length; index += 1) {
    const line = all[index];
    if (line.trimStart().startsWith('#')) continue;
    const assignment = ASSIGNMENT.exec(line);
    if (assignment) {
      const value = parseValue(assignment[2]);
      if (value !== null) entries.set(assignment[1], { value, line });
      continue;
    }
    const bare = BARE_KEY.exec(line);
    if (bare) entries.set(bare[1], { value: null, line });
  }
  return entries;
}

function hasUnusualSpace(line) {
  for (const char of line) {
    const code = char.codePointAt(0);
    if (UNUSUAL_SPACES.has(code) || (code >= 0x2000 && code <= 0x200a)) return true;
  }
  return false;
}

function ambiguous(text) {
  return lines(text.startsWith(BOM) ? text.slice(1) : text).some((line) => {
    if (line.trimStart().startsWith('#')) return false;
    if (hasUnusualSpace(line) || QUOTED_KEY.test(line)) return true;
    const assignment = ANY_ASSIGNMENT.exec(line);
    return Boolean(assignment) && unterminated(assignment[1]);
  });
}

function acceptableSecret(key) {
  return typeof key === 'string' && key.length >= MINIMUM_SECRET_LENGTH && !PLACEHOLDER_SECRETS.has(key.trim().toLowerCase());
}

function stripLikePython(text) {
  let start = 0;
  let end = text.length;
  while (start < end && PYTHON_SPACE.includes(text[start])) start += 1;
  while (end > start && PYTHON_SPACE.includes(text[end - 1])) end -= 1;
  return text.slice(start, end);
}

function strictText(bytes) {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    return null;
  }
}

function pythonDotenvKey(python, folder, { timeout = 20000, env = process.env } = {}) {
  return new Promise((resolve) => {
    const childEnv = Object.fromEntries(Object.entries(env).filter(([key]) => key.toUpperCase() !== KEY_NAME));
    let child;
    try {
      child = execFile(python, ['-I', '-B', '-'], {
        cwd: folder,
        env: childEnv,
        timeout,
        killSignal: 'SIGKILL',
        windowsHide: true,
        encoding: 'utf8',
        maxBuffer: 1024 * 1024,
      }, (error, stdout) => {
        if (error) {
          resolve(undefined);
          return;
        }
        try {
          const value = JSON.parse(stdout.trim());
          resolve(value === null || typeof value === 'string' ? value : undefined);
        } catch {
          resolve(undefined);
        }
      });
    } catch {
      resolve(undefined);
      return;
    }
    child.stdin.on('error', quiet);
    child.stdin.end(DOTENV_SCRIPT);
  });
}

async function nearestFile(folder, name, platform) {
  const logical = path.resolve(folder);
  const start = platform === 'win32' ? logical : await fsp.realpath(folder).catch(() => logical);
  let current = start;
  for (;;) {
    const candidate = path.join(current, name);
    const info = await fsp.stat(candidate).catch(() => null);
    if (info && info.isFile()) return { file: candidate, size: info.size, shown: current === start ? path.join(logical, name) : candidate };
    const parent = path.dirname(current);
    if (parent === current) return null;
    current = parent;
  }
}

async function readSettings(folder, platform) {
  const found = {};
  const files = [];
  let unclear = null;
  for (const name of SETTINGS_FILES) {
    const nearest = await nearestFile(folder, name, platform);
    if (!nearest) continue;
    if (nearest.size > SETTINGS_LIMIT) return { problem: 'unclear', file: nearest.shown };
    const text = strictText(await fsp.readFile(nearest.file));
    if (text === null) return { problem: 'unclear', file: nearest.shown };
    const entries = readEnv(text);
    if (platform === 'win32' && [...entries.keys()].some((key) => key !== KEY_NAME && key.toUpperCase() === KEY_NAME)) {
      return { problem: 'unclear', file: nearest.shown };
    }
    if (!unclear && ambiguous(text)) unclear = nearest.shown;
    files.push(nearest.shown);
    found[name] = { entry: entries.get(KEY_NAME), file: nearest.shown };
  }
  const env = found['.env'];
  const flaskenv = found['.flaskenv'];
  const result = { files, unclear, entry: null, file: env ? env.file : flaskenv ? flaskenv.file : null };
  if (env && env.entry && env.entry.value !== null) return { ...result, entry: env.entry, file: env.file };
  if (flaskenv && flaskenv.entry && flaskenv.entry.value !== null) {
    return env && env.entry ? { problem: 'unclear', file: env.file } : { ...result, entry: flaskenv.entry, file: flaskenv.file };
  }
  return result;
}

async function startsEncrypted(file) {
  const handle = await fsp.open(file, 'r');
  try {
    const { bytesRead, buffer } = await handle.read(Buffer.alloc(8), 0, 8, 0);
    const head = buffer.subarray(0, bytesRead);
    return ENCRYPTED_PREFIXES.some((prefix) => head.length >= prefix.length && head.subarray(0, prefix.length).equals(prefix));
  } finally {
    await handle.close();
  }
}

async function holdsEncryptedData(dir) {
  const skipped = new Set([path.join(dir, KEY_FILE), path.join(dir, TOKEN_FILE)]);
  return walkFiles(dir, (item, info) => info.isFile() && !skipped.has(item) && startsEncrypted(item));
}

async function keyFileDecision(folder) {
  const file = path.join(folder, 'data', KEY_FILE);
  const info = await lstatOrNull(file);
  if (!info) return { keyFile: 'none' };
  if (!info.isFile() || info.size > SETTINGS_LIMIT) return { problem: 'unclear', file };
  const content = await fsp.readFile(file);
  if (content.some((byte) => byte > 0x7f)) return { problem: 'unsupported', file };
  if (acceptableSecret(stripLikePython(content.toString('latin1').replace(/\r\n?/g, '\n')))) return { keyFile: 'keep' };
  return (await holdsEncryptedData(path.join(folder, 'data'))) ? { problem: 'weak', file } : { keyFile: 'drop' };
}

async function settleUsedKey(value, folder, file) {
  if (!acceptableSecret(value)) {
    return (await holdsEncryptedData(path.join(folder, 'data'))) ? { problem: 'weak', file } : keyFileDecision(folder);
  }
  return KEY_FILE_SAFE.test(value) ? { carry: value, file } : { problem: 'unsupported', file };
}

async function resolveKey(folder, { python, timeout, env, platform, log }) {
  const fromEnvironment = env[KEY_NAME];
  if (typeof fromEnvironment === 'string' && fromEnvironment !== '') {
    log('SECRET_KEY is set in the environment, so the earlier version used it');
    return settleUsedKey(fromEnvironment, folder, null);
  }
  const settings = await readSettings(folder, platform);
  if (settings.problem) return settings;
  let value = settings.entry ? settings.entry.value : null;
  if (settings.files.length) {
    let interpreter = null;
    try {
      interpreter = typeof python === 'function' ? await python() : python;
    } catch (error) {
      log('looking for Python failed:', error.code || error.message);
    }
    const truth = interpreter ? await pythonDotenvKey(interpreter, folder, { timeout, env }) : undefined;
    log(truth === undefined ? `read ${settings.files.join(', ')} without Python` : `checked ${settings.files.join(', ')} with ${interpreter}`);
    if (truth === undefined) {
      if (settings.unclear) return { problem: 'unclear', file: settings.unclear };
    } else if (truth === null) {
      value = null;
    } else if (truth !== value) {
      return { problem: 'unclear', file: settings.file };
    }
  }
  if (value === null) return keyFileDecision(folder);
  if (INTERPOLATION.test(value)) return { problem: 'unclear', file: settings.file };
  return settleUsedKey(value, folder, settings.file);
}

async function copyTree(source, destination, skipped) {
  await fsp.mkdir(destination);
  for (const name of await fsp.readdir(source)) {
    const from = path.join(source, name);
    const to = path.join(destination, name);
    const info = await fsp.lstat(from);
    if (info.isDirectory()) {
      await copyTree(from, to, skipped);
    } else if (info.isFile()) {
      await fsp.copyFile(from, to, fs.constants.COPYFILE_EXCL);
      if (process.platform !== 'win32') await flush(to);
    } else {
      skipped.push(from);
    }
  }
}

async function flush(file) {
  const handle = await fsp.open(file, 'r');
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function writeKey(file, key) {
  const handle = await fsp.open(file, 'wx', 0o600);
  try {
    await handle.writeFile(key, 'utf8');
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function applyKey(data, decision) {
  const file = path.join(data, KEY_FILE);
  if (decision.carry !== undefined) {
    await fsp.rm(file, { recursive: true, force: true });
    await writeKey(file, decision.carry);
    return 'carried';
  }
  if (decision.keyFile === 'drop') {
    await fsp.rm(file, { recursive: true, force: true });
    return 'dropped';
  }
  return decision.keyFile === 'keep' ? 'kept' : 'none';
}

async function ownerOnly(target) {
  const info = await fsp.lstat(target);
  if (info.isDirectory()) {
    await fsp.chmod(target, 0o700);
    for (const name of await fsp.readdir(target)) await ownerOnly(path.join(target, name));
  } else if (info.isFile()) {
    await fsp.chmod(target, info.mode & 0o111 ? 0o700 : 0o600);
  }
}

async function workFolder(target) {
  const folder = await fsp.mkdtemp(path.join(target, WORK_PREFIX));
  await fsp.writeFile(path.join(folder, MARKER), '', { mode: 0o600, flag: 'wx' });
  return folder;
}

async function cleanUp(target) {
  let names;
  try {
    names = await fsp.readdir(target);
  } catch {
    return;
  }
  for (const name of names) {
    if (!WORK_NAME.test(name)) continue;
    const folder = path.join(target, name);
    try {
      if (!(await fsp.lstat(folder)).isDirectory()) continue;
      if (!(await fsp.lstat(path.join(folder, MARKER))).isFile()) continue;
      await fsp.rm(folder, { recursive: true, force: true });
    } catch {}
  }
}

async function retrying(operation) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      if (process.platform !== 'win32' || attempt >= RETRIES || !RETRIED_ERRORS.has(error.code)) throw error;
      await delay(250 * attempt);
    }
  }
}

function moveIntoPlace(source, destination) {
  return retrying(() => fsp.rename(source, destination));
}

async function availableSpace(dir) {
  try {
    const stats = await fsp.statfs(dir);
    return stats.bavail * stats.bsize;
  } catch {
    return null;
  }
}

async function importLegacyData({
  legacy,
  target,
  python = null,
  timeout,
  env = process.env,
  platform = process.platform,
  portFree = async () => true,
  freeSpace = availableSpace,
  beforeMove = null,
  move = moveIntoPlace,
  log = quiet,
}) {
  const dataDir = path.join(target, 'data');
  let staging = null;
  try {
    if ((await dataState(dataDir)) === 'used') return { outcome: 'skipped' };
    const decision = await resolveKey(legacy, { python, timeout, env, platform, log });
    if (decision.problem) return { outcome: decision.problem, file: decision.file };
    const source = path.join(legacy, 'data');
    await fsp.mkdir(target, { recursive: true });
    const size = await measure(source);
    const needed = size.bytes + SPACE_RESERVE;
    const free = await freeSpace(target);
    if (typeof free === 'number' && free < needed) return { outcome: 'space', needed, free };
    if (!(await portFree())) return { outcome: 'busy' };
    await cleanUp(target);
    staging = await workFolder(target);
    const copied = path.join(staging, 'data');
    const skipped = [];
    await copyTree(source, copied, skipped);
    if (skipped.length) log(`left out ${skipped.length} links or special files: ${skipped.join(', ')}`);
    const key = await applyKey(copied, decision);
    if (process.platform !== 'win32') await ownerOnly(staging);
    if (beforeMove) await beforeMove(target);
    if (!(await portFree())) return { outcome: 'busy' };
    const state = await dataState(dataDir);
    if (state === 'used') return { outcome: 'skipped' };
    const replaced = path.join(staging, 'replaced');
    try {
      if (state === 'empty') await retrying(() => fsp.rmdir(dataDir));
      if (state === 'unused') await move(dataDir, replaced);
      await move(copied, dataDir);
    } catch (error) {
      if ((await lstatOrNull(replaced)) && !(await lstatOrNull(dataDir))) await move(replaced, dataDir).catch(quiet);
      if ((await dataState(dataDir).catch(() => null)) === 'used') return { outcome: 'skipped' };
      throw error;
    }
    return { outcome: 'imported', key, files: size.files, replaced: state === 'unused' };
  } catch (error) {
    log('taking over the earlier data failed:', error && error.message ? error.message : String(error));
    return { outcome: 'failed', code: error && error.code ? String(error.code) : null };
  } finally {
    if (staging) await fsp.rm(staging, { recursive: true, force: true }).catch(quiet);
  }
}

module.exports = {
  KEY_FILE,
  MINIMUM_SECRET_LENGTH,
  PLACEHOLDER_SECRETS,
  acceptableSecret,
  ambiguous,
  candidateFolders,
  cleanUp,
  dataState,
  findLegacyFolders,
  importLegacyData,
  isFresh,
  pythonDotenvKey,
  readEnv,
};
