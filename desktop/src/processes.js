// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { execFile, spawnSync } = require('child_process');
const fs = require('fs');
const net = require('net');
const path = require('path');

const isWindows = process.platform === 'win32';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function system32(...parts) {
  return path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', ...parts);
}

function run(file, args, timeout = 5000) {
  return new Promise((resolve) => {
    let child;
    try {
      child = execFile(file, args, { timeout, windowsHide: true, encoding: 'utf8' }, (error, stdout) => {
        resolve(error ? null : stdout);
      });
    } catch {
      resolve(null);
      return;
    }
    if (child.stdin) {
      child.stdin.on('error', () => {});
      child.stdin.end();
    }
  });
}

function firstLine(text) {
  return (text || '').trim().split(/\r?\n/)[0].trim();
}

async function findPython(root) {
  for (const dir of ['venv', '.venv', 'env']) {
    const candidate = isWindows ? path.join(root, dir, 'Scripts', 'python.exe') : path.join(root, dir, 'bin', 'python3');
    if (fs.existsSync(candidate)) return candidate;
  }
  const locator = isWindows ? system32('where.exe') : '/usr/bin/which';
  for (const command of isWindows ? ['python', 'python3'] : ['python3', 'python']) {
    const found = firstLine(await run(locator, [isWindows ? `$PATH:${command}` : command]));
    if (found && /^Python 3\./.test(firstLine(await run(found, ['--version'])))) return found;
  }
  if (isWindows) {
    const launcher = firstLine(await run(locator, ['$PATH:py']));
    const resolved = launcher ? firstLine(await run(launcher, ['-3', '-X', 'utf8', '-c', 'import sys; print(sys.executable)'])) : '';
    if (resolved && fs.existsSync(resolved)) return resolved;
  }
  return null;
}

function validPid(pid) {
  return Number.isInteger(pid) && pid > 0;
}

function isAlive(pid) {
  if (!validPid(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

async function identify(pid) {
  if (!validPid(pid)) return null;
  if (process.platform === 'linux') {
    try {
      return fs.readlinkSync(`/proc/${pid}/exe`).replace(/ \(deleted\)$/, '');
    } catch {
      return null;
    }
  }
  if (isWindows) {
    const out = await run(
      system32('WindowsPowerShell', 'v1.0', 'powershell.exe'),
      ['-NoProfile', '-NonInteractive', '-Command', `[Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-CimInstance Win32_Process -Filter "ProcessId=${pid}").ExecutablePath`],
      15000,
    );
    return out && out.trim() ? out.trim() : null;
  }
  const out = await run('/bin/ps', ['-o', 'comm=', '-p', String(pid)]);
  return out && out.trim() ? out.trim() : null;
}

function canonical(file) {
  try {
    return fs.realpathSync.native(file);
  } catch {
    return file;
  }
}

function samePath(a, b) {
  if (!a || !b) return false;
  return isWindows ? path.normalize(a).toLowerCase() === path.normalize(b).toLowerCase() : a === b;
}

function signalGroup(pid, signal) {
  try {
    process.kill(-pid, signal);
    return true;
  } catch {
    try {
      process.kill(pid, signal);
      return true;
    } catch {
      return false;
    }
  }
}

function groupAlive(pid) {
  if (!validPid(pid) || isWindows) return false;
  try {
    process.kill(-pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

function signalGroupOnly(pid, signal) {
  if (!validPid(pid) || isWindows) return;
  try {
    process.kill(-pid, signal);
  } catch {}
}

function killTree(pid, { force = false } = {}) {
  if (!validPid(pid)) return Promise.resolve();
  if (isWindows) {
    return run(system32('taskkill.exe'), ['/PID', String(pid), '/T', '/F'], 15000).then(() => undefined);
  }
  signalGroup(pid, force ? 'SIGKILL' : 'SIGTERM');
  return Promise.resolve();
}

function killTreeSync(pid) {
  if (!validPid(pid)) return;
  if (isWindows) {
    spawnSync(system32('taskkill.exe'), ['/PID', String(pid), '/T', '/F'], { windowsHide: true, timeout: 5000 });
    return;
  }
  signalGroup(pid, 'SIGKILL');
}

function isPortTaken(port) {
  return new Promise((resolve) => {
    const socket = net.connect(port, '127.0.0.1');
    socket.once('connect', () => {
      socket.destroy();
      resolve(true);
    });
    socket.once('error', () => resolve(false));
    socket.setTimeout(2000, () => {
      socket.destroy();
      resolve(true);
    });
  });
}

async function waitForPortFree(port, timeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (!(await isPortTaken(port))) return true;
    await delay(150);
  }
  return !(await isPortTaken(port));
}

module.exports = {
  canonical,
  delay,
  findPython,
  groupAlive,
  identify,
  isAlive,
  isPortTaken,
  killTree,
  killTreeSync,
  samePath,
  signalGroupOnly,
  system32,
  validPid,
  waitForPortFree,
};
