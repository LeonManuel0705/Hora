// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app } = require('electron');
const { spawn } = require('child_process');
const crypto = require('crypto');
const EventEmitter = require('events');
const fs = require('fs');
const http = require('http');
const path = require('path');
const config = require('./config');
const { log, openBackendLog } = require('./log');
const processes = require('./processes');
const store = require('./store');

const READY_TIMEOUT = 60000;
const SLOW_AFTER = 8000;
const VERY_SLOW_AFTER = 30000;
const RECORDS = 'backends';

function probe(pathname, { method = 'GET', headers = {} } = {}) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const request = http.request(`${config.hubOrigin}${pathname}`, { method, headers }, (response) => {
      const chunks = [];
      let size = 0;
      response.on('data', (chunk) => {
        size += chunk.length;
        if (size > 4096) {
          request.destroy();
          finish(null);
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => finish({ status: response.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      response.on('error', () => finish(null));
    });
    const deadline = setTimeout(() => {
      request.destroy();
      finish(null);
    }, 3000);
    request.setTimeout(2000, () => {
      request.destroy();
      finish(null);
    });
    request.on('error', () => finish(null));
    request.on('close', () => {
      clearTimeout(deadline);
      finish(null);
    });
    request.end();
  });
}

async function handshake(token) {
  const nonce = crypto.randomBytes(32).toString('hex');
  const reply = await probe(`/api/desktop-handshake?nonce=${nonce}`);
  if (!reply) return 'unreachable';
  if (reply.status !== 200) return reply.status >= 500 ? 'unreachable' : 'mismatch';
  let mac;
  try {
    mac = JSON.parse(reply.body).mac;
  } catch {
    return 'mismatch';
  }
  if (typeof mac !== 'string' || !/^[0-9a-f]{64}$/.test(mac)) return 'mismatch';
  const expected = crypto.createHmac('sha256', token).update(`hub-desktop-handshake:${nonce}`).digest();
  return crypto.timingSafeEqual(expected, Buffer.from(mac, 'hex')) ? 'ok' : 'mismatch';
}

async function answersHandshake(token) {
  return (await handshake(token)) === 'ok';
}

async function proveBackend(token, attempts = 3) {
  let result = 'unreachable';
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (attempt) await new Promise((resolve) => setTimeout(resolve, 300 * 2 ** attempt));
    result = await handshake(token);
    if (result !== 'unreachable') return result;
  }
  return result;
}

async function requestLoginCode(token) {
  if ((await proveBackend(token)) !== 'ok') return null;
  const reply = await probe('/api/desktop-login-code', { method: 'POST', headers: { 'X-Hub-Token': token } });
  if (!reply || reply.status !== 200) return null;
  try {
    return JSON.parse(reply.body).code ?? null;
  } catch {
    return null;
  }
}

const hasAppPy = (dir) => Boolean(dir) && fs.existsSync(path.join(dir, 'app', 'app.py'));

function frozenServer() {
  const exe = process.platform === 'win32' ? 'server.exe' : 'server';
  const candidate = path.join(process.resourcesPath || '', 'backend', 'server', exe);
  return fs.existsSync(candidate) ? candidate : null;
}

function plausibleServer(identity) {
  if (!app.isPackaged) return true;
  const own = frozenServer();
  if (own && processes.samePath(processes.canonical(own), identity)) return true;
  return process.platform === 'linux' && /\/resources\/backend\/server\/server$/.test(identity);
}

function projectRoot() {
  const override = config.devSetting('HUB_ROOT');
  if (hasAppPy(override)) return override;
  const parent = path.resolve(config.appDir, '..');
  return hasAppPy(parent) ? parent : null;
}

async function devPython(root) {
  const override = config.devSetting('HUB_DEV_PYTHON');
  if (override) return fs.existsSync(override) ? override : null;
  return processes.findPython(root);
}

async function launchPlan() {
  if (app.isPackaged) {
    const server = frozenServer();
    if (!server) return { problem: { kind: 'missing' } };
    return { command: server, args: [], cwd: path.dirname(server) };
  }
  const root = projectRoot();
  if (!root) return { problem: { kind: 'project' } };
  const python = await devPython(root);
  if (!python) return { problem: { kind: 'python' } };
  return { command: python, args: ['-m', 'app.app'], cwd: root };
}

const INHERITED_SETTINGS = ['SECRET_KEY', 'DATABASE_URL', 'CORS_ORIGINS', 'HUB_HTTPS', 'GOOGLE_REDIRECT_URI', 'FLASK_ENV', 'FLASK_DEBUG'];

function backendEnv(token, dataDir) {
  const inherited = { ...process.env };
  if (app.isPackaged) {
    for (const key of Object.keys(inherited)) {
      if (INHERITED_SETTINGS.includes(key.toUpperCase())) delete inherited[key];
    }
  }
  const env = {
    ...inherited,
    HUB_EXIT_WITH_PARENT: '1',
    HUB_HOST: '127.0.0.1',
    HUB_PORT: String(config.port),
    HUB_DATA_DIR: dataDir,
    HUB_ALLOW_UNSAFE_WERKZEUG: '1',
    HUB_DESKTOP_TOKEN: token,
    PYTHONUNBUFFERED: '1',
    PYTHONIOENCODING: 'utf-8',
  };
  if (config.isDev && config.port !== 5050) env.CORS_ORIGINS = config.hubOrigin;
  if (app.isPackaged) Object.assign(env, { FLASK_SKIP_DOTENV: '1', PYTHON_DOTENV_DISABLED: '1' });
  return env;
}

class Backend extends EventEmitter {
  constructor({ token, dataDir }) {
    super();
    this.token = token;
    this.dataDir = dataDir;
    this.child = null;
    this.ready = false;
    this.stopping = null;
    this.lastExit = null;
    this.spawnError = null;
    this.closed = false;
  }

  get running() {
    return this.child !== null;
  }

  records() {
    const saved = store.get(RECORDS);
    if (!Array.isArray(saved)) return [];
    return saved.filter((entry) => entry && processes.validPid(entry.pid) && typeof entry.identity === 'string');
  }

  saveRecords(records) {
    store.set(RECORDS, records.length ? records : null, { now: true });
  }

  forget(pid) {
    this.saveRecords(this.records().filter((entry) => entry.pid !== pid));
  }

  async clearLeftovers(progress) {
    const records = this.records();
    if (!records.length) return;
    const leftovers = [];
    for (const record of records) {
      if (!processes.isAlive(record.pid)) {
        if (processes.groupAlive(record.pid)) {
          log(`processes of the old backend ${record.pid} are still running, stopping them`);
          processes.signalGroupOnly(record.pid, 'SIGKILL');
        }
        continue;
      }
      const identity = await processes.identify(record.pid);
      if (processes.samePath(identity, record.identity) && plausibleServer(identity)) leftovers.push(record.pid);
      else log(`recorded backend ${record.pid} is not ours anymore (${identity || 'unknown'})`);
    }
    if (!leftovers.length) {
      this.saveRecords([]);
      return;
    }
    progress('leftover');
    for (const pid of leftovers) {
      log(`stopping leftover backend ${pid}`);
      await processes.killTree(pid);
    }
    const deadline = Date.now() + 4000;
    while (Date.now() < deadline && leftovers.some((pid) => processes.isAlive(pid))) await processes.delay(150);
    for (const pid of leftovers.filter((pid) => processes.isAlive(pid))) {
      log(`leftover backend ${pid} ignored the request, forcing it`);
      await processes.killTree(pid, { force: true });
    }
    for (const pid of leftovers) processes.signalGroupOnly(pid, 'SIGKILL');
    await processes.waitForPortFree(config.port, 3000);
    this.saveRecords(this.records().filter((entry) => processes.isAlive(entry.pid) && !leftovers.includes(entry.pid)));
    progress('starting');
  }

  attach(child, plan) {
    this.child = child;
    this.ready = false;
    this.lastExit = null;
    this.spawnError = null;
    const out = openBackendLog();
    out.write(`\n--- ${new Date().toISOString()} ${path.basename(plan.command)} (pid ${child.pid}) ---\n`);
    child.stdout.on('data', (chunk) => out.write(chunk));
    child.stderr.on('data', (chunk) => out.write(chunk));
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      out.end();
    };
    child.once('close', close);
    child.once('error', (error) => {
      log('backend process error:', error.message);
      this.spawnError = error;
      if (this.child !== child) return;
      this.child = null;
      this.ready = false;
      close();
    });
    child.once('exit', (code, signal) => {
      log(`backend ${child.pid} exited (code ${code}, signal ${signal})`);
      this.lastExit = { code, signal };
      setTimeout(close, 5000);
      if (this.child !== child) return;
      const wasReady = this.ready;
      this.child = null;
      this.ready = false;
      if (this.stopping) this.forget(child.pid);
      else this.reapGroup(child.pid);
      if (wasReady && !this.stopping) this.emit('crashed', { code, signal });
    });
  }

  async reapGroup(pid) {
    if (!processes.groupAlive(pid)) {
      this.forget(pid);
      return;
    }
    log(`backend ${pid} left processes behind, stopping them`);
    processes.signalGroupOnly(pid, 'SIGTERM');
    const deadline = Date.now() + 3000;
    while (Date.now() < deadline && processes.groupAlive(pid)) await processes.delay(150);
    processes.signalGroupOnly(pid, 'SIGKILL');
    if (!processes.groupAlive(pid)) this.forget(pid);
  }

  async remember(child, command) {
    let identity = processes.canonical(command);
    if (process.platform !== 'win32') identity = (await processes.identify(child.pid)) || identity;
    if (this.child === child) this.saveRecords([{ pid: child.pid, identity }]);
  }

  async waitUntilReady(child, progress) {
    const started = Date.now();
    let hint = 0;
    while (this.child === child) {
      if (await answersHandshake(this.token)) return this.child === child ? 'ready' : 'exited';
      const elapsed = Date.now() - started;
      if (elapsed >= READY_TIMEOUT) return 'timeout';
      if (hint === 0 && elapsed >= SLOW_AFTER) {
        hint = 1;
        progress('slow');
      } else if (hint === 1 && elapsed >= VERY_SLOW_AFTER) {
        hint = 2;
        progress('verySlow');
      }
      await processes.delay(400);
    }
    return 'exited';
  }

  async start(progress) {
    if (this.child) await this.stop();
    progress('starting');
    await this.clearLeftovers(progress);
    if (await processes.isPortTaken(config.port)) {
      log(`port ${config.port} is taken by a process that is not ours`);
      return { ok: false, problem: { kind: 'port' } };
    }
    if (this.closed) return { ok: false, problem: { kind: 'closed' } };
    const plan = await launchPlan();
    if (this.closed) return { ok: false, problem: { kind: 'closed' } };
    if (plan.problem) {
      log('backend not startable:', plan.problem.kind);
      return { ok: false, problem: plan.problem };
    }
    fs.mkdirSync(this.dataDir, { recursive: true });
    let child;
    try {
      child = spawn(plan.command, plan.args, {
        cwd: plan.cwd,
        env: backendEnv(this.token, this.dataDir),
        stdio: ['pipe', 'pipe', 'pipe'],
        windowsHide: true,
        detached: process.platform !== 'win32',
      });
    } catch (error) {
      log('backend spawn failed:', error);
      return { ok: false, problem: { kind: 'spawn', code: error.code || null } };
    }
    child.stdin.on('error', () => {});
    this.attach(child, plan);
    if (!processes.validPid(child.pid)) {
      await processes.delay(50);
      if (this.child === child) this.child = null;
      return { ok: false, problem: { kind: 'spawn', code: this.spawnError ? this.spawnError.code : null } };
    }
    log(`backend started: ${plan.command} (pid ${child.pid})`);
    this.saveRecords([{ pid: child.pid, identity: processes.canonical(plan.command) }]);
    const outcome = await this.waitUntilReady(child, progress);
    if (outcome === 'ready') {
      this.ready = true;
      log(`backend ready on ${config.hubOrigin}`);
      await this.remember(child, plan.command);
      return { ok: true };
    }
    if (outcome === 'timeout') {
      log('backend did not answer in time');
      await this.stop();
      return { ok: false, problem: { kind: 'timeout' } };
    }
    if (this.spawnError) return { ok: false, problem: { kind: 'spawn', code: this.spawnError.code || null } };
    return { ok: false, problem: { kind: 'exited', ...(this.lastExit || {}) } };
  }

  stop() {
    if (this.stopping) return this.stopping;
    const child = this.child;
    if (!child) return Promise.resolve();
    this.stopping = (async () => {
      const exited = child.exitCode !== null || child.signalCode !== null
        ? Promise.resolve()
        : new Promise((resolve) => child.once('exit', resolve));
      const within = (ms) => Promise.race([exited.then(() => true), processes.delay(ms).then(() => false)]);
      log(`stopping backend ${child.pid}`);
      await processes.killTree(child.pid);
      if (!(await within(4000))) {
        log(`backend ${child.pid} did not stop, forcing it`);
        await processes.killTree(child.pid, { force: true });
        await within(2000);
      }
      processes.signalGroupOnly(child.pid, 'SIGKILL');
      if (this.child === child) {
        this.child = null;
        this.ready = false;
      }
      if (!processes.isAlive(child.pid) && !processes.groupAlive(child.pid)) this.forget(child.pid);
    })().finally(() => {
      this.stopping = null;
    });
    return this.stopping;
  }

  close() {
    this.closed = true;
    return this.stop();
  }

  stopNow() {
    if (!this.child) return;
    processes.killTreeSync(this.child.pid);
    this.forget(this.child.pid);
    this.child = null;
  }
}

module.exports = { Backend, answersHandshake, proveBackend, requestLoginCode };
