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

const COUNT_WORDS = ['null', 'eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun', 'zehn'];

const earlierProducts = (brand.previousNames || []).join(' oder ');

function sizeText(bytes) {
  for (const [unit, factor] of [['GB', 1024 ** 3], ['MB', 1024 ** 2]]) {
    if (bytes >= factor) return `${(bytes / factor).toFixed(1).replace('.', ',')} ${unit}`;
  }
  return `${Math.ceil(bytes / 1024)} KB`;
}

function fileName(file) {
  return file ? file.split(/[\\/]/).pop() : null;
}

function dateText(ms) {
  const date = new Date(ms);
  const two = (value) => String(value).padStart(2, '0');
  return `${two(date.getDate())}.${two(date.getMonth() + 1)}.${date.getFullYear()}`;
}

function earlierNames(found) {
  return [...new Set(found.map((item) => item.name))].join(' oder ');
}

const takeover = {
  question(found) {
    const earlier = earlierNames(found);
    const message = `Daten aus ${earlier} gefunden`;
    const choices = ['Neu anfangen', 'Beenden'];
    const final = `Fängst du neu an, fragt ${name} nicht noch einmal.`;
    if (found.length === 1) {
      return {
        message,
        detail: `Im Ordner „${found[0].folder}“ liegen deine Daten aus der Zeit, als ${name} noch ${earlier} hieß. Soll ${name} sie übernehmen? Der alte Ordner bleibt als Sicherung, wie er ist. ${final}`,
        buttons: ['Übernehmen', ...choices],
      };
    }
    const list = found
      .map((item, index) => `${index + 1}. „${item.folder}“${item.newest ? `, zuletzt geändert am ${dateText(item.newest)}` : ''}`)
      .join('\n');
    return {
      message,
      detail: `Deine Daten aus der Zeit, als ${name} noch ${earlier} hieß, liegen in ${COUNT_WORDS[found.length] || found.length} Ordnern:\n\n${list}\n\nWelchen soll ${name} übernehmen? Die alten Ordner bleiben als Sicherung, wie sie sind. ${final}`,
      buttons: [...found.map((_item, index) => `Ordner ${index + 1} übernehmen`), ...choices],
    };
  },
  importing: (earlier) => `Daten aus ${earlier} werden übernommen …`,
};

function takeoverProblem(info, withLog) {
  const earlier = info.name || 'der alten Version';
  const kept = 'Der alte Ordner ist unverändert.';
  const again = 'Beim nächsten Versuch kannst du auch neu anfangen.';
  const heading = `Die Daten aus ${earlier} wurden nicht übernommen.`;
  const file = fileName(info.file);
  switch (info.outcome) {
    case 'unclear':
      return {
        heading,
        message: `Die Datei „${file || '.env'}“ lässt sich nicht eindeutig lesen. Prüf sie, zum Beispiel auf ein fehlendes Anführungszeichen, und versuch es noch einmal. ${again}`,
        detail: info.file || null,
        actions: withLog,
      };
    case 'unsupported':
      return {
        heading,
        message: `${file ? `Der Schlüssel in der Datei „${file}“` : 'Der SECRET_KEY aus deiner Umgebung'} enthält Zeichen, die ${name} nicht übernehmen kann, und ohne ihn wären deine gespeicherten Zugangsdaten unlesbar. ${again}`,
        detail: info.file || null,
        actions: withLog,
      };
    case 'weak':
      return {
        heading,
        message: `Ein Teil davon ist mit einem Beispielschlüssel oder einem zu kurzen Schlüssel verschlüsselt, den ${name} aus Sicherheitsgründen nicht mehr verwendet. ${name} würde diese Teile leer anzeigen. ${kept} ${again}`,
        detail: info.file || null,
        actions: withLog,
      };
    case 'busy':
      return {
        heading: `Port ${port} ist schon belegt.`,
        message: `Vielleicht läuft ${earlier} noch. Beende ${earlier} und versuch es noch einmal, dann übernimmt ${name} deine Daten.`,
        actions: { retry: labels.retry },
      };
    case 'space':
      return {
        heading: 'Für die Übernahme fehlt Speicherplatz.',
        message: `${name} braucht dafür etwa ${sizeText(info.needed)} freien Speicherplatz, frei sind nur ${sizeText(info.free)}. Gib etwas Platz frei und versuch es noch einmal. ${kept}`,
        actions: { retry: labels.retry },
      };
    default:
      return {
        heading: `Die Übernahme aus ${earlier} hat nicht geklappt.`,
        message: `${kept} Versuch es noch einmal. Klappt es wieder nicht, steht im Protokoll, woran es liegt.`,
        detail: info.code ? `Fehler ${info.code}` : null,
        actions: withLog,
      };
  }
}

function problem(kind, info = {}) {
  const withLog = { retry: labels.retry, log: labels.log };
  switch (kind) {
    case 'port':
      return {
        heading: `Port ${port} ist schon belegt.`,
        message: `Dort läuft ein anderes Programm, zum Beispiel ${earlierProducts ? `${earlierProducts} oder ` : ''}ein älteres ${name}, das noch im Hintergrund läuft, oder eines aus dem Terminal. Beende es und versuch es noch einmal.`,
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
    case 'takeover':
      return takeoverProblem(info, withLog);
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

module.exports = { progress, labels, problem, tray, backgroundHint, update, menu, takeover };
