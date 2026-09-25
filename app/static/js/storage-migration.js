// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

(() => {
  for (const store of [window.localStorage, window.sessionStorage]) {
    try {
      Object.keys(store)
        .filter(key => /^nexus[-_]/.test(key))
        .forEach(key => {
          const target = 'app' + key.slice('nexus'.length);
          if (store.getItem(target) === null) store.setItem(target, store.getItem(key));
          store.removeItem(key);
        });
    } catch (e) {}
  }
})();
