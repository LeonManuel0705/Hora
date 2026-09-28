// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const { brand, port } = require('./config');

const name = brand.name;

const progress = {
  starting: 'Server wird gestartet …',
  leftover: `Ein älterer Server von ${name} läuft noch und wird beendet …`,
  slow: 'Beim ersten Start nach einer Installation dauert das etwas länger.',
  verySlow: `Das dauert ungewöhnlich lange. ${name} wartet noch bis zu 30 Sekunden.`,
};

const labels = {
  retry: 'Erneut versuchen',
  log: 'Protokoll öffnen',
  link: 'Von python.org herunterladen',
};

function exitDetail({ code, signal } = {}) {
  if (signal) return `Beendet durch ${signal}`;
  if (code !== undefined && code !== null) return `Exit-Code ${code}`;
  return null;
}

function problem(kind, info = {}) {
  const withLog = { retry: labels.retry, log: labels.log };
  switch (kind) {
    case 'port':
      return {
        heading: `Port ${port} ist schon belegt.`,
        message: `Dort läuft ein anderes Programm, zum Beispiel ein älteres ${name}, das noch im Hintergrund läuft, oder eines aus dem Terminal. Beende es und versuch es noch einmal.`,
        actions: { retry: labels.retry },
      };
    case 'crashed':
      return {
        heading: 'Der Server wurde unerwartet beendet.',
        message: `Mit „${labels.retry}“ startet ${name} ihn neu.`,
        detail: exitDetail(info),
        actions: withLog,
      };
    case 'exited':
      return {
        heading: 'Der Server hat sich beim Start beendet.',
        message: 'Woran es lag, steht im Protokoll. Versuch es noch einmal.',
        detail: exitDetail(info),
        actions: withLog,
      };
    case 'timeout':
      return {
        heading: 'Der Server antwortet nicht.',
        message: 'Nach 60 Sekunden kam noch keine Antwort. Versuch es noch einmal.',
        actions: withLog,
      };
    case 'spawn':
      return {
        heading: 'Der Server ließ sich nicht starten.',
        message: `Versuch es noch einmal. Klappt es dann auch nicht, installier ${name} neu. Deine Daten bleiben dabei erhalten.`,
        detail: info.code ? `Fehler ${info.code}` : null,
        actions: withLog,
      };
    case 'missing':
      return {
        heading: 'Der Server fehlt in dieser Installation.',
        message: `Installier ${name} neu. Deine Daten bleiben dabei erhalten.`,
        actions: { retry: labels.retry },
      };
    case 'project':
      return {
        heading: 'Projektordner nicht gefunden.',
        message: 'Erwartet wird app/app.py im Ordner über desktop oder in HUB_ROOT.',
        actions: { retry: labels.retry },
      };
    case 'python':
      return {
        heading: 'Python 3 wurde nicht gefunden.',
        message: 'Bitte installiere Python 3.',
        actions: { retry: labels.retry, link: labels.link },
      };
    case 'identity':
      return {
        heading: `Der Server auf Port ${port} hat sich nicht als ${name} ausgewiesen.`,
        message: 'Versuch es noch einmal.',
        actions: { retry: labels.retry },
      };
    case 'unreachable':
      return {
        heading: 'Der Server antwortet gerade nicht.',
        message: 'Versuch es noch einmal. Hilft das nicht, steht im Protokoll, woran es liegt.',
        actions: withLog,
      };
    case 'renderer':
      return {
        heading: 'Die Ansicht ist mehrmals abgestürzt.',
        message: `Versuch es noch einmal. Hilft das nicht, starte ${name} neu.`,
        actions: withLog,
      };
    case 'page':
      return {
        heading: `${name} ließ sich nicht laden.`,
        message: 'Versuch es noch einmal.',
        detail: info.description || null,
        actions: withLog,
      };
    default:
      return {
        heading: 'Etwas ist schiefgegangen.',
        message: 'Versuch es noch einmal.',
        actions: withLog,
      };
  }
}

const tray = {
  open: `${name} öffnen`,
  note: 'Schnelle Notiz',
  quit: 'Beenden',
};

function backgroundHint(platform) {
  const where = {
    win32: 'per Rechtsklick auf das Symbol im Infobereich der Taskleiste',
    darwin: 'über das Symbol in der Menüleiste',
  }[platform] || 'über das Symbol in der Leiste';
  const note = platform === 'darwin' ? '⌘⌥N' : 'Strg+Alt+N';
  return {
    title: `${name} läuft im Hintergrund weiter`,
    body: `Mit ${note} schreibst du von überall eine schnelle Notiz. Beenden kannst du ${name} ${where}.`,
  };
}

const update = {
  title: 'Neues Update verfügbar',
  newsTitle: 'Neuheiten',
  version: (versionName) => `Version ${versionName}`,
  installed: (version) => `Installiert: ${version}`,
  labels: { download: 'Herunterladen', later: 'Später', skip: 'Überspringen' },
  notification: (versionName) => ({
    title: `${name} ${versionName} ist verfügbar`,
    body: 'Klick hier, um das Update herunterzuladen.',
  }),
};

const menu = {
  undo: 'Rückgängig',
  redo: 'Wiederholen',
  cut: 'Ausschneiden',
  copy: 'Kopieren',
  paste: 'Einfügen',
  selectAll: 'Alles auswählen',
  copyLink: 'Link kopieren',
  learnSpelling: 'Zum Wörterbuch hinzufügen',
};

module.exports = { progress, labels, problem, tray, backgroundHint, update, menu };
