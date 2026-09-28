// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

function parseUrl(value) {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function isHubUrl(value, hubOrigin) {
  const url = parseUrl(value);
  return Boolean(url) && url.protocol === 'http:' && url.origin === hubOrigin && !url.username && !url.password;
}

function isHubOrigin(value, hubOrigin) {
  const url = parseUrl(value || '');
  return Boolean(url) && url.origin === hubOrigin && !url.username && !url.password;
}

function isNewerVersion(remote, current) {
  const parts = (value) => value.split('.').map((part) => (/^[+-]?\d+$/.test(part) ? Number(part) : Number.NaN));
  const remoteParts = parts(remote);
  const currentParts = parts(current);
  if (remoteParts.some(Number.isNaN) || currentParts.some(Number.isNaN)) return remote !== current;
  for (let i = 0; i < remoteParts.length && i < currentParts.length; i++) {
    if (remoteParts[i] > currentParts[i]) return true;
    if (remoteParts[i] < currentParts[i]) return false;
  }
  return remoteParts.length > currentParts.length;
}

function trustedUpdateUrl(value, { website, repository }) {
  const url = parseUrl(value);
  if (!url || url.protocol !== 'https:' || url.username || url.password) return false;
  const host = url.hostname.toLowerCase();
  const site = new URL(website).hostname.toLowerCase();
  if (host === site || host.endsWith(`.${site}`)) return true;
  if (host !== 'github.com') return false;
  const releases = `${new URL(repository).pathname}/releases/`.toLowerCase();
  return url.pathname.toLowerCase().startsWith(releases);
}

function browserLoginUrl(hubUrl, code) {
  if (typeof code !== 'string' || !/^[0-9a-f]{64}$/.test(code)) return null;
  const url = parseUrl(hubUrl);
  if (!url || url.protocol !== 'http:' || url.hostname !== '127.0.0.1') return null;
  url.search = '';
  url.searchParams.set('login_code', code);
  return url.href;
}

module.exports = { browserLoginUrl, isHubOrigin, isHubUrl, isNewerVersion, parseUrl, trustedUpdateUrl };
