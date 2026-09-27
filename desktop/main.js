// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { app, BrowserWindow, shell } = require('electron');
const path = require('path');
const { spawn, execSync } = require('child_process');
const fs = require('fs');
const http = require('http');
const os = require('os');
const brand = require('./brand.json');
const crypto = require('crypto');

const PORT = 5050;

// Handed to the backend in its environment and used once to establish the
// WebView's session, so opening the hub needs no manual token.
const DESKTOP_TOKEN = crypto.randomBytes(32).toString('hex');
const HUB_URL = `http://localhost:${PORT}/hub?token=${DESKTOP_TOKEN}`;

function useUserDataDir() {
  const appData = app.getPath('appData');
  const target = path.join(appData, brand.name);
  const previous = ['Nexus', 'nexus'].map(name => path.join(appData, name)).find(dir => fs.existsSync(dir));
  if (previous && !fs.existsSync(target)) fs.renameSync(previous, target);
  app.setPath('userData', target);
}

useUserDataDir();

let mainWindow = null;
let flaskProcess = null;

const hasAppPy = (dir) => dir && fs.existsSync(path.join(dir, 'app', 'app.py'));

// The Flask backend is shipped as electron-builder extraResources under
// process.resourcesPath/backend in a packaged app.
function getBundledBackendPath() {
  const candidate = path.join(process.resourcesPath || '', 'backend');
  return hasAppPy(candidate) ? candidate : null;
}

// The bundled backend lives in a read-only resources directory, but Flask needs
// to write its data/ and secret key. Copy it once into a writable per-user
// location, NEVER overwriting an existing copy (which holds the user's data).
function ensureWritableBackend() {
  const bundled = getBundledBackendPath();
  if (!bundled) return null;

  const dest = path.join(app.getPath('userData'), 'backend');
  if (!hasAppPy(dest)) {
    fs.mkdirSync(dest, { recursive: true });
    fs.cpSync(path.join(bundled, 'app'), path.join(dest, 'app'), { recursive: true });
    for (const f of ['requirements.txt', 'calendar_sync.py']) {
      const src = path.join(bundled, f);
      if (fs.existsSync(src)) fs.copyFileSync(src, path.join(dest, f));
    }
  }
  return dest;
}

function findProjectRoot() {
  // Dev: running `electron .` from inside the source tree.
  const parent = path.resolve(__dirname, '..');
  if (hasAppPy(parent)) return parent;

  if (hasAppPy(process.env.HUB_ROOT)) return process.env.HUB_ROOT;

  // Packaged: extract the bundled backend into a writable per-user directory.
  try {
    const writable = ensureWritableBackend();
    if (hasAppPy(writable)) return writable;
  } catch (e) {
    console.error(`${brand.name}: backend extraction failed:`, e);
  }

  const home = os.homedir();
  for (const candidate of [
    path.join(home, 'Documents', brand.name),
    path.join(home, brand.name),
  ]) {
    if (hasAppPy(candidate)) return candidate;
  }

  return null;
}

function findPython(projectRoot) {
  const isWin = process.platform === 'win32';

  for (const venv of ['venv', '.venv', 'env']) {
    const p = isWin
      ? path.join(projectRoot, venv, 'Scripts', 'python.exe')
      : path.join(projectRoot, venv, 'bin', 'python3');
    if (fs.existsSync(p)) return p;
  }

  if (isWin) {
    for (const cmd of ['python', 'python3']) {
      try {
        const version = execSync(`${cmd} --version`, {
          encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'],
        }).trim();
        if (version.includes('Python 3')) {
          try {
            return execSync(`where ${cmd}`, {
              encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'],
            }).trim().split(/\r?\n/)[0];
          } catch (_) { return cmd; }
        }
      } catch (_) {}
    }
    try {
      const pyPath = execSync('py -3 -c "import sys; print(sys.executable)"', {
        encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'],
      }).trim();
      if (pyPath && fs.existsSync(pyPath)) return pyPath;
    } catch (_) {}
  } else {
    for (const cmd of ['python3', 'python']) {
      try {
        const version = execSync(`${cmd} --version`, {
          encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'],
        }).trim();
        if (version.includes('Python 3')) {
          try {
            return execSync(`which ${cmd}`, {
              encoding: 'utf8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'],
            }).trim();
          } catch (_) { return cmd; }
        }
      } catch (_) {}
    }
  }

  return null;
}

function isServerRunning() {
  return new Promise((resolve) => {
    const req = http.get(`http://localhost:${PORT}/`, (res) => {
      res.resume();
      resolve(true);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(2000, () => { req.destroy(); resolve(false); });
  });
}

async function waitForServer(maxRetries = 30, interval = 500) {
  for (let i = 0; i < maxRetries; i++) {
    if (await isServerRunning()) return true;
    await new Promise((r) => setTimeout(r, interval));
  }
  return false;
}

// Writable per-user data directory the backend persists into (honored via
// HUB_DATA_DIR — see app/paths.py). Stable across app updates.
function dataDir() {
  return path.join(app.getPath('userData'), 'data');
}

// Path to the bundled PyInstaller-frozen backend, if this build shipped one.
// When present the app needs NO system Python at all.
function getFrozenBackend() {
  const exe = process.platform === 'win32' ? 'server.exe' : 'server';
  const candidate = path.join(process.resourcesPath || '', 'backend', 'server', exe);
  return fs.existsSync(candidate) ? candidate : null;
}

function backendEnv() {
  return {
    ...process.env,
    HUB_HOST: '127.0.0.1',
    HUB_DATA_DIR: dataDir(),
    // Permits app.py's __main__ runner to use the Werkzeug server, which is what
    // a local single-user loopback server wants (the frozen entry forces it
    // regardless). This used to be FLASK_ENV='development', but that same value
    // also switched off SESSION_COOKIE_SECURE.
    HUB_ALLOW_UNSAFE_WERKZEUG: '1',
    HUB_DESKTOP_TOKEN: DESKTOP_TOKEN,
  };
}

function spawnBackend(command, args, cwd) {
  fs.mkdirSync(dataDir(), { recursive: true });

  flaskProcess = spawn(command, args, {
    cwd,
    env: backendEnv(),
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    // Own process group on POSIX so we can kill the backend and any children it
    // spawned as a group (avoids orphans).
    detached: process.platform !== 'win32',
  });

  // Without an 'error' handler an async spawn failure (e.g. bad interpreter
  // path) emits an unhandled 'error' event that crashes the main process.
  flaskProcess.on('error', (err) => {
    console.error(`Flask spawn error: ${err && err.message}`);
    flaskProcess = null;
  });

  flaskProcess.stdout.on('data', (data) => {
    console.log(`Flask: ${data.toString().trim()}`);
  });

  flaskProcess.stderr.on('data', (data) => {
    console.log(`Flask: ${data.toString().trim()}`);
  });

  flaskProcess.on('exit', (code) => {
    console.log(`Flask exited with code ${code}`);
    flaskProcess = null;
  });
}

// Run the frozen standalone backend (no Python needed). cwd = its own dir so
// PyInstaller's onedir loader finds its _internal/ payload.
function startFrozenBackend(exePath) {
  spawnBackend(exePath, [], path.dirname(exePath));
}

// Run the backend from Python source (fallback when no frozen binary shipped).
function startFlask(projectRoot, pythonPath) {
  spawnBackend(pythonPath, ['-m', 'app.app'], projectRoot);
}

function killFlask() {
  if (!flaskProcess) return;
  const proc = flaskProcess;
  flaskProcess = null;
  try {
    if (process.platform === 'win32') {
      spawn('taskkill', ['/pid', proc.pid.toString(), '/f', '/t'], {
        stdio: 'ignore',
      });
    } else {
      // Kill the whole process group (negative pid) since we spawned detached.
      try {
        process.kill(-proc.pid, 'SIGTERM');
      } catch (_) {
        proc.kill('SIGTERM');
      }
    }
  } catch (_) {}
}

function getLoadingHTML() {
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    height: 100vh; display: flex; flex-direction: column;
    justify-content: center; align-items: center;
    background: linear-gradient(135deg, #0F172A, #1E293B);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    color: white; overflow: hidden;
  }
  .title {
    font-size: 32px; font-weight: 700; letter-spacing: 4px;
    background: linear-gradient(135deg, #667EEA, #764BA2);
    -webkit-background-clip: text; -webkit-text-fill-color: transparent;
  }
  .spinner {
    width: 32px; height: 32px; margin-top: 36px;
    border: 2.5px solid rgba(255,255,255,0.08);
    border-top-color: #667EEA; border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  .status { color: rgba(255,255,255,0.4); font-size: 13px; margin-top: 16px; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style></head><body>
  <div class="title">${brand.name}</div>
  <div class="spinner"></div>
  <div class="status">Server wird gestartet...</div>
</body></html>`;
}

function getErrorHTML(title, message, showPythonLink) {
  const pythonLink = showPythonLink
    ? '<a href="https://www.python.org/downloads/" style="color:#667EEA;text-decoration:none;margin-top:16px;display:inline-block;font-size:14px;">Python herunterladen &rarr;</a>'
    : '';
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    height: 100vh; display: flex; flex-direction: column;
    justify-content: center; align-items: center;
    background: linear-gradient(135deg, #0F172A, #1E293B);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    color: white; overflow: hidden;
  }
  .title {
    font-size: 32px; font-weight: 700; letter-spacing: 4px;
    background: linear-gradient(135deg, #667EEA, #764BA2);
    -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    margin-bottom: 36px;
  }
  .error-box {
    max-width: 420px; padding: 24px; border-radius: 16px;
    background: rgba(239,68,68,0.12); border: 1px solid rgba(239,68,68,0.25);
    text-align: center;
  }
  .error-title { font-size: 16px; font-weight: 600; margin-bottom: 10px; }
  .error-msg { font-size: 13px; color: rgba(255,255,255,0.6); line-height: 1.6; }
</style></head><body>
  <div class="title">${brand.name}</div>
  <div class="error-box">
    <div class="error-title">${title}</div>
    <div class="error-msg">${message}</div>
    ${pythonLink}
  </div>
</body></html>`;
}

if (process.platform === 'win32') {
  app.disableHardwareAcceleration();
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(async () => {
    mainWindow = new BrowserWindow({
      width: 1200,
      height: 800,
      minWidth: 400,
      minHeight: 600,
      title: brand.name,
      icon: path.join(__dirname, 'resources', 'icon.png'),
      backgroundColor: '#0f0f1a',
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
      },
      autoHideMenuBar: true,
      show: false,
    });

    mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(getLoadingHTML())}`);
    mainWindow.once('ready-to-show', () => mainWindow.show());

    if (await isServerRunning()) {
      console.log(`${brand.name}: Flask already running, connecting...`);
      mainWindow.loadURL(HUB_URL);
      setupNavigation();
      return;
    }

    // Preferred path: a bundled frozen backend needs no system Python at all.
    const frozen = getFrozenBackend();
    if (frozen) {
      console.log(`${brand.name}: Using bundled backend: ${frozen}`);
      try {
        startFrozenBackend(frozen);
      } catch (err) {
        mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(
          getErrorHTML('Startfehler', 'Server konnte nicht gestartet werden.')
        )}`);
        return;
      }
    } else {
      // Fallback: run the Python source (requires a system Python 3).
      const projectRoot = findProjectRoot();
      if (!projectRoot) {
        mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(
          getErrorHTML(
            'Projekt nicht gefunden',
            `Der Projektordner mit app/app.py wurde nicht gefunden.<br>Erwartet in: ~/Documents/${brand.name}`
          )
        )}`);
        return;
      }

      const pythonPath = findPython(projectRoot);
      if (!pythonPath) {
        mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(
          getErrorHTML(
            'Python 3 nicht gefunden',
            `Bitte installiere Python 3 und starte ${brand.name} erneut.`,
            true
          )
        )}`);
        return;
      }

      console.log(`${brand.name}: Project root: ${projectRoot}`);
      console.log(`${brand.name}: Python: ${pythonPath}`);

      try {
        startFlask(projectRoot, pythonPath);
      } catch (err) {
        mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(
          getErrorHTML('Startfehler', 'Server konnte nicht gestartet werden.')
        )}`);
        return;
      }
    }

    const ready = await waitForServer();
    if (ready) {
      mainWindow.loadURL(HUB_URL);
      setupNavigation();
    } else {
      mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(
        getErrorHTML('Timeout', 'Server konnte nicht innerhalb von 15s gestartet werden.')
      )}`);
    }

    mainWindow.on('closed', () => { mainWindow = null; });
  });

  // Only hand http/https/mailto URLs to the OS — never file:, javascript:, or
  // other schemes an embedded page might try to trigger.
  function safeOpenExternal(url) {
    try {
      const proto = new URL(url).protocol;
      if (proto === 'http:' || proto === 'https:' || proto === 'mailto:') {
        shell.openExternal(url);
      }
    } catch (_) {}
  }

  function setupNavigation() {
    if (!mainWindow) return;

    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
      if (!url.startsWith(`http://localhost:${PORT}`) &&
          !url.startsWith(`http://127.0.0.1:${PORT}`)) {
        safeOpenExternal(url);
        return { action: 'deny' };
      }
      return { action: 'allow' };
    });

    mainWindow.webContents.on('will-navigate', (event, url) => {
      if (!url.startsWith(`http://localhost:${PORT}`) &&
          !url.startsWith(`http://127.0.0.1:${PORT}`)) {
        event.preventDefault();
        safeOpenExternal(url);
      }
    });

    mainWindow.webContents.on('did-finish-load', () => {
      mainWindow.webContents.executeJavaScript(`
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.getRegistrations().then(regs => {
            regs.forEach(r => r.unregister());
          });
          caches.keys().then(keys => {
            keys.filter(k => k.startsWith('app-')).forEach(k => caches.delete(k));
          });
        }
      `).catch(() => {});
    });
  }

  app.on('window-all-closed', () => {
    killFlask();
    app.quit();
  });

  // Belt-and-suspenders: also terminate the backend if the app quits by any
  // other path (Cmd+Q on macOS, app.quit(), a crash) so Python is never
  // orphaned and left holding port 5050.
  app.on('before-quit', killFlask);
  app.on('will-quit', killFlask);
  process.on('exit', killFlask);
  process.on('uncaughtException', (err) => {
    console.error('Uncaught exception:', err);
    killFlask();
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
    }
  });
}
