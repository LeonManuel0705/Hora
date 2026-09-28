// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { execFile } = require('child_process');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');

const KEY_NAME = 'SECRET_KEY';
const KEY_FILE = '.secret_key';
const MARKER = '.import-work';
const WORK_PREFIX = '.data-import-';
const WORK_NAME = /^\.data-import-[A-Za-z0-9]{6}$/;
const MINIMUM_SECRET_LENGTH = 32;
const PLACEHOLDER_SECRETS = new Set(['your-secret-key-here', 'secret-key-change-me', 'changeme', 'please-change-me']);
const ENV_LIMIT = 1024 * 1024;
const SPACE_RESERVE = 64 * 1024 * 1024;
const MOVE_ATTEMPTS = 8;
const RETRIED_MOVE_ERRORS = new Set(['EPERM', 'EACCES', 'EBUSY']);
const DOTENV_SCRIPT = 'import json, sys; from dotenv import dotenv_values; print(json.dumps(dotenv_values(sys.argv[1])))';

const ASSIGNMENT = /^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*=[ \t]*(.*)$/;
const BARE_KEY = /^[ \t]*(?:export[ \t]+)?([^=#\s]+)[ \t]*(?:#.*)?$/;
const ANY_ASSIGNMENT = /^[ \t]*(?:export[ \t]+)?[^=#\s]+[ \t]*=[ \t]*(.*)$/;
const QUOTED_KEY = /^[ \t]*(?:export[ \t]+)?['"]/;
const TRAILER = /^[ \t]*(?:#.*)?$/;
const UNUSUAL_SPACES = new Set([0x0b, 0x0c, 0x1c, 0x1d, 0x1e, 0x1f, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff]);
const BOM = String.fromCharCode(0xfeff);
const REPLACEMENT_CHARACTER = String.fromCharCode(0xfffd);
const KEY_FILE_SAFE = /^[\x21-\x7e](?:[\x20-\x7e]*[\x21-\x7e])?$/;
const PYTHON_SPACE = ' \t\n\r\x0b\x0c\x1c\x1d\x1e\x1f';
const DOUBLE_ESCAPES = { '\\': '\\', "'": "'", '"': '"', a: '\x07', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t', v: '\v' };
const SINGLE_ESCAPES = { '\\': '\\', "'": "'" };

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

async function isRealDirectory(target) {
  try {
    const info = await fsp.lstat(target);
    return info.isDirectory();
  } catch {
    return false;
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

async function measure(dir) {
  const total = { files: 0, bytes: 0, newest: null };
  const walk = async (current) => {
    for (const name of await fsp.readdir(current)) {
      const item = path.join(current, name);
      const info = await fsp.lstat(item);
      if (info.isDirectory()) {
        await walk(item);
      } else if (info.isFile()) {
        total.files += 1;
        total.bytes += info.size;
        total.newest = Math.max(total.newest || 0, info.mtimeMs);
      }
    }
  };
  await walk(dir);
  return total;
}

async function findLegacyFolders(folders, { target }) {
  const targetIdentity = await identity(target);
  const seen = new Set();
  const found = [];
  for (const folder of folders) {
    const data = path.join(folder, 'data');
    if (!(await isRealDirectory(folder)) || !(await isRealDirectory(data))) continue;
    let entries;
    try {
      entries = await fsp.readdir(data);
    } catch {
      continue;
    }
    if (!entries.length) continue;
    const id = await identity(folder);
    if (seen.has(id) || contains(id, targetIdentity) || contains(targetIdentity, id)) continue;
    seen.add(id);
    const size = await measure(data).catch(() => ({ files: null, bytes: null, newest: null }));
    found.push({ folder, name: path.basename(folder), ...size });
  }
  return found;
}

async function dataState(dir) {
  const info = await lstatOrNull(dir);
  if (!info) return 'missing';
  if (!info.isDirectory()) return 'used';
  return (await fsp.readdir(dir)).length ? 'used' : 'empty';
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

function providedValue(value) {
  return typeof value === 'string' && value !== '' && !value.includes(REPLACEMENT_CHARACTER) && !value.includes('${') && acceptableSecret(value);
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

function plainValues(parsed) {
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
  const values = new Map();
  for (const [key, value] of Object.entries(parsed)) {
    if (value !== null && typeof value !== 'string') return null;
    values.set(key, value);
  }
  return values;
}

function dotenvValues(python, file, { cwd, timeout = 20000 } = {}) {
  return new Promise((resolve) => {
    try {
      execFile(python, ['-I', '-B', '-c', DOTENV_SCRIPT, file], {
        cwd,
        timeout,
        killSignal: 'SIGKILL',
        windowsHide: true,
        encoding: 'utf8',
        maxBuffer: 16 * 1024 * 1024,
      }, (error, stdout) => {
        if (error) {
          resolve(null);
          return;
        }
        try {
          resolve(plainValues(JSON.parse(stdout.trim())));
        } catch {
          resolve(null);
        }
      });
    } catch {
      resolve(null);
    }
  });
}

async function legacyKey(folder, { python = null, timeout } = {}) {
  const file = path.join(folder, '.env');
  const info = await lstatOrNull(file);
  if (!info) return { key: null };
  if (!info.isFile() || info.size > ENV_LIMIT) return { problem: 'unclear' };
  const text = strictText(await fsp.readFile(file));
  if (text === null) return { key: null };
  const entries = readEnv(text);
  const truth = python ? await dotenvValues(python, file, { cwd: folder, timeout }) : null;
  if (!truth && ambiguous(text)) return { problem: 'unclear' };
  const entry = entries.get(KEY_NAME);
  const value = truth ? truth.get(KEY_NAME) : entry && entry.value;
  if (!providedValue(value) || (entry && entry.line.includes('${'))) return { key: null };
  if (!entry || entry.value !== value) return { problem: 'unclear' };
  if (!KEY_FILE_SAFE.test(value)) return { problem: 'unsupported' };
  return { key: value };
}

async function copyTree(source, destination) {
  await fsp.mkdir(destination);
  for (const name of await fsp.readdir(source)) {
    const from = path.join(source, name);
    const to = path.join(destination, name);
    const info = await fsp.lstat(from);
    if (info.isDirectory()) await copyTree(from, to);
    else if (info.isFile()) await fsp.copyFile(from, to, fs.constants.COPYFILE_EXCL);
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

async function settleKey(data, key) {
  const file = path.join(data, KEY_FILE);
  const info = await lstatOrNull(file);
  if (key !== null) {
    if (info) await fsp.rm(file, { recursive: true, force: true });
    await writeKey(file, key);
    return 'carried';
  }
  if (!info) return 'none';
  if (info.isFile()) {
    const content = await fsp.readFile(file);
    if (content.some((byte) => byte > 0x7f) || acceptableSecret(stripLikePython(content.toString('latin1')))) return 'kept';
  }
  await fsp.rm(file, { recursive: true, force: true });
  return 'dropped';
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

async function moveIntoPlace(source, destination) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await fsp.rename(source, destination);
      return;
    } catch (error) {
      if (process.platform !== 'win32' || attempt >= MOVE_ATTEMPTS || !RETRIED_MOVE_ERRORS.has(error.code)) throw error;
      await delay(250 * attempt);
    }
  }
}

async function availableSpace(dir) {
  try {
    const stats = await fsp.statfs(dir);
    return stats.bavail * stats.bsize;
  } catch {
    return null;
  }
}

async function importLegacyData({ legacy, target, python = null, timeout, freeSpace = availableSpace, beforeMove = null }) {
  const dataDir = path.join(target, 'data');
  let staging = null;
  try {
    if ((await dataState(dataDir)) === 'used') return { outcome: 'skipped' };
    const settings = await legacyKey(legacy, { python, timeout });
    if (settings.problem) return { outcome: settings.problem };
    const source = path.join(legacy, 'data');
    await fsp.mkdir(target, { recursive: true });
    const size = await measure(source);
    const free = await freeSpace(target);
    if (typeof free === 'number' && free < size.bytes + SPACE_RESERVE) return { outcome: 'space', needed: size.bytes, free };
    await cleanUp(target);
    staging = await workFolder(target);
    const copied = path.join(staging, 'data');
    await copyTree(source, copied);
    const key = await settleKey(copied, settings.key);
    if (process.platform !== 'win32') await ownerOnly(staging);
    if (beforeMove) await beforeMove(target);
    const state = await dataState(dataDir);
    if (state === 'used') return { outcome: 'skipped' };
    try {
      if (state === 'empty') await fsp.rmdir(dataDir);
      await moveIntoPlace(copied, dataDir);
    } catch (error) {
      if ((await dataState(dataDir).catch(() => null)) === 'used') return { outcome: 'skipped' };
      throw error;
    }
    return { outcome: 'imported', key, files: size.files };
  } catch (error) {
    return { outcome: 'failed', code: error && error.code ? String(error.code) : null };
  } finally {
    if (staging) await fsp.rm(staging, { recursive: true, force: true }).catch(() => {});
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
  dotenvValues,
  findLegacyFolders,
  importLegacyData,
  isFresh,
  legacyKey,
  readEnv,
};
