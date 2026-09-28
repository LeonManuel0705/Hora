// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const assert = require('node:assert/strict');
const test = require('node:test');
const brand = require('../brand.json');
const { isHubOrigin, isHubUrl, isNewerVersion, trustedUpdateUrl } = require('../src/rules');

const hub = 'http://127.0.0.1:5050';
const site = new URL(brand.website);

test('a remote version is newer only by its numbers, a longer one wins a tie', () => {
  assert.equal(isNewerVersion('0.5', '0.5.0'), false);
  assert.equal(isNewerVersion('0.5.0', '0.5.0'), false);
  assert.equal(isNewerVersion('0.4', '0.5.0'), false);
  assert.equal(isNewerVersion('0.5.1', '0.5.0'), true);
  assert.equal(isNewerVersion('0.6', '0.5.0'), true);
  assert.equal(isNewerVersion('0.10', '0.9.9'), true);
  assert.equal(isNewerVersion('0.5.0', '0.5'), true);
});

test('versions that are not plain numbers only count as new when they differ', () => {
  assert.equal(isNewerVersion('1.0-beta', '0.5.0'), true);
  assert.equal(isNewerVersion('beta', 'beta'), false);
  assert.equal(isNewerVersion('0.5.', '0.5.0'), true);
});

test('update links must be https on the website or the release pages of the repository', () => {
  const trusted = (url) => trustedUpdateUrl(url, brand);
  assert.equal(trusted(`${brand.website}/download#windows`), true);
  assert.equal(trusted(`https://sub.${site.hostname}/x`), true);
  assert.equal(trusted(`${brand.repository}/releases/tag/v1`), true);
  assert.equal(trusted(`${brand.repository.toLowerCase()}/RELEASES/latest`), true);
  assert.equal(trusted(`http://${site.hostname}/download`), false);
  assert.equal(trusted(`https://${site.hostname}.evil.example/`), false);
  assert.equal(trusted(`${brand.repository}/issues`), false);
  assert.equal(trusted(`${brand.repository}/releases/../../evil`), false);
  assert.equal(trusted(`https://evil.example@${site.hostname}/`), false);
  assert.equal(trusted(`https://${site.hostname}@evil.example/`), false);
  assert.equal(trusted('javascript:alert(1)'), false);
  assert.equal(trusted('not a url'), false);
});

test('only the loopback hub origin counts as the hub', () => {
  assert.equal(isHubUrl(`${hub}/hub`, hub), true);
  assert.equal(isHubUrl(`${hub}/hub/klassisch?x=1`, hub), true);
  assert.equal(isHubUrl('http://localhost:5050/hub', hub), false);
  assert.equal(isHubUrl('http://127.0.0.1:5051/hub', hub), false);
  assert.equal(isHubUrl('https://127.0.0.1:5050/hub', hub), false);
  assert.equal(isHubUrl('http://user:pw@127.0.0.1:5050/hub', hub), false);
  assert.equal(isHubUrl('file:///etc/passwd', hub), false);
  assert.equal(isHubUrl('javascript:alert(1)', hub), false);
});

test('permission origins match with or without a trailing slash', () => {
  assert.equal(isHubOrigin(`${hub}/`, hub), true);
  assert.equal(isHubOrigin(hub, hub), true);
  assert.equal(isHubOrigin(`${hub}/hub`, hub), true);
  assert.equal(isHubOrigin('file:///', hub), false);
  assert.equal(isHubOrigin('http://localhost:5050/', hub), false);
  assert.equal(isHubOrigin('', hub), false);
  assert.equal(isHubOrigin(undefined, hub), false);
});
