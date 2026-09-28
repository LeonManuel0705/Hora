// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const api = window.shellScreen;
const byId = (id) => document.getElementById(id);

const stage = byId('stage');
const loading = byId('loading');
const problem = byId('problem');
const status = byId('status');
const buttons = [...document.querySelectorAll('[data-action]')];

let view = null;
let ready = false;
let queued = null;

function enter(node) {
  node.removeAttribute('data-entering');
  void node.offsetWidth;
  node.setAttribute('data-entering', '');
  clearTimeout(node.enterTimer);
  node.enterTimer = setTimeout(() => node.removeAttribute('data-entering'), 800);
}

function showLoading(state) {
  const text = state.status || '';
  if (view !== 'loading') {
    problem.hidden = true;
    loading.hidden = false;
    status.textContent = text;
    if (view) enter(loading);
  } else if (status.textContent !== text) {
    status.textContent = text;
    enter(status);
  }
  view = 'loading';
}

function showProblem(state) {
  byId('heading').textContent = state.heading || '';
  byId('message').textContent = state.message || '';
  const detail = byId('detail');
  detail.textContent = state.detail || '';
  detail.hidden = !state.detail;

  for (const button of buttons) {
    const label = state.actions ? state.actions[button.dataset.action] : null;
    button.hidden = !label;
    button.disabled = false;
    if (label) button.querySelector('[data-label]').textContent = label;
  }

  if (view !== 'problem') {
    loading.hidden = true;
    problem.hidden = false;
    if (view) enter(problem);
  }
  view = 'problem';
}

function render(state, first) {
  if (!state) return;
  document.title = state.name || '';
  byId('name').textContent = state.name || '';
  if (state.view === 'problem') showProblem(state);
  else showLoading(state);
  if (first) {
    stage.setAttribute('data-ready', '');
    enter(stage);
  }
}

for (const button of buttons) {
  button.addEventListener('click', () => {
    if (button.disabled) return;
    button.disabled = true;
    const action = button.dataset.action;
    api.act(action).finally(() => {
      if (action !== 'retry') setTimeout(() => (button.disabled = false), 600);
    });
  });
}

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' || view !== 'problem') return;
  if (document.activeElement && document.activeElement !== document.body) return;
  const retry = buttons.find((button) => button.dataset.action === 'retry' && !button.hidden);
  if (retry) {
    event.preventDefault();
    retry.click();
  }
});

api.onState((state) => {
  if (ready) render(state, false);
  else queued = state;
});

api.init().then((state) => {
  ready = true;
  render(queued || state, true);
  queued = null;
});
