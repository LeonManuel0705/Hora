// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const fs = require('fs');
const path = require('path');
const { log } = require('./log');

let file = null;
let data = {};
let timer = null;

function load(dir) {
  file = path.join(dir, 'shell-state.json');
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) data = parsed;
  } catch (error) {
    if (error.code !== 'ENOENT') log('shell state unreadable, starting fresh:', error.message);
  }
}

function flush() {
  clearTimeout(timer);
  timer = null;
  if (!file) return;
  const temporary = `${file}.tmp`;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(temporary, JSON.stringify(data, null, 2));
    fs.renameSync(temporary, file);
  } catch (error) {
    log('shell state not saved:', error.message);
  }
}

function get(key) {
  return data[key];
}

function set(key, value, { now = false } = {}) {
  if (value === undefined || value === null) delete data[key];
  else data[key] = value;
  if (now) flush();
  else if (!timer) timer = setTimeout(flush, 500);
}

module.exports = { load, get, set, flush };
