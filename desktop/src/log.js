// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const fs = require('fs');
const path = require('path');

const SHELL_LIMIT = 512 * 1024;
const BACKEND_LIMIT = 2 * 1024 * 1024;

let directory = null;
let stream = null;
const early = [];

function previousName(file) {
  return file.replace(/\.log$/, '.1.log');
}

function rotate(file, limit) {
  try {
    if (fs.statSync(file).size > limit) fs.renameSync(file, previousName(file));
  } catch {}
}

function text(part) {
  if (part instanceof Error) return part.stack || part.message;
  if (typeof part === 'string') return part;
  try {
    return JSON.stringify(part);
  } catch {
    return String(part);
  }
}

function log(...parts) {
  const line = `${new Date().toISOString()} ${parts.map(text).join(' ')}`;
  console.log(line);
  if (stream) stream.write(`${line}\n`);
  else if (!directory && early.length < 200) early.push(line);
}

function openLogs(dir) {
  directory = dir;
  try {
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'shell.log');
    rotate(file, SHELL_LIMIT);
    stream = fs.createWriteStream(file, { flags: 'a' });
    stream.on('error', () => {
      stream = null;
    });
    for (const line of early.splice(0)) stream.write(`${line}\n`);
  } catch {
    stream = null;
  }
}

function backendLogFile() {
  return directory ? path.join(directory, 'backend.log') : null;
}

function openBackendLog() {
  const file = backendLogFile();
  if (!file) return { write() {}, end() {} };
  let size = 0;
  let out = null;
  let ended = false;
  const start = (flags) => {
    try {
      size = flags === 'a' && fs.existsSync(file) ? fs.statSync(file).size : 0;
      out = fs.createWriteStream(file, { flags });
      out.on('error', () => {
        out = null;
      });
    } catch {
      out = null;
    }
  };
  rotate(file, BACKEND_LIMIT);
  start('a');
  return {
    write(chunk) {
      if (!out) return;
      out.write(chunk);
      size += chunk.length;
      if (size <= BACKEND_LIMIT) return;
      const full = out;
      out = null;
      full.once('close', () => {
        try {
          fs.renameSync(file, previousName(file));
        } catch {}
        if (!ended) start('w');
      });
      full.end();
    },
    end() {
      ended = true;
      if (out) out.end();
      out = null;
    },
  };
}

module.exports = { log, openLogs, openBackendLog, backendLogFile, logDirectory: () => directory };
