// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const api = window.shellUpdate;
const byId = (id) => document.getElementById(id);
const dialog = byId('dialog');
const choices = [...document.querySelectorAll('[data-choice]')];

let closing = false;

function fill(info) {
  document.title = info.title;
  byId('title').textContent = info.title;
  byId('version').textContent = info.version;
  byId('newsTitle').textContent = info.newsTitle;
  byId('installed').textContent = info.installed;
  const items = info.changelog.map((line) => {
    const item = document.createElement('li');
    item.textContent = line;
    return item;
  });
  byId('newsList').replaceChildren(...items);
  byId('news').hidden = items.length === 0;
  for (const button of choices) {
    button.querySelector('[data-label]').textContent = info.labels[button.dataset.choice] || '';
  }
}

function choose(choice) {
  if (closing) return;
  closing = true;
  document.body.dataset.state = 'leaving';
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  setTimeout(() => api.choose(choice), still ? 0 : 180);
}

function trapFocus(event) {
  const index = choices.indexOf(document.activeElement);
  const step = event.shiftKey ? -1 : 1;
  const start = event.shiftKey ? choices.length - 1 : 0;
  const next = index === -1 ? start : (index + step + choices.length) % choices.length;
  event.preventDefault();
  choices[next].focus();
}

document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-choice]');
  if (button) choose(button.dataset.choice);
  else if (!dialog.contains(event.target)) choose('later');
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    event.preventDefault();
    choose('later');
  } else if (event.key === 'Tab') {
    trapFocus(event);
  }
});

api.init().then((info) => {
  if (!info) return;
  fill(info);
  document.body.dataset.state = 'entering';
  setTimeout(() => {
    if (!closing) document.body.dataset.state = 'open';
  }, 450);
  dialog.focus({ preventScroll: true });
});
