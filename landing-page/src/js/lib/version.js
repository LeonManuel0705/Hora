let pending = null;

export function versionInfo() {
  if (!pending) {
    pending = fetch("/version.json", { cache: "no-cache" })
      .then((res) => (res.ok ? res.json() : null))
      .catch(() => null);
  }
  return pending;
}

export function fillVersion(root) {
  const slots = root.querySelectorAll("[data-version]");
  if (!slots.length) return;
  versionInfo().then((info) => {
    if (!info) return;
    slots.forEach((el) => {
      const kind = el.dataset.version;
      if (kind === "full" && info.versionName) el.textContent = `Version ${info.versionName}, Build ${info.buildNumber}.`;
      if (kind === "short" && info.version) el.textContent = `v${info.version}`;
    });
  });
}
