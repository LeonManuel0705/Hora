// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const webStartScript = r'''
(function () {
  var root = document.documentElement;
  root.dataset.shell = "web";
  var host = null;
  try {
    if (window.parent !== window && window.parent.location.origin === location.origin) host = window.parent;
  } catch (error) {}
  function send(type, value) {
    if (host) host.postMessage({ source: "hub", type: type, value: value }, location.origin);
  }
  var viewport = host && host.visualViewport;
  function insets() {
    var probe = host && host.document.getElementById("hub-safe-area");
    var style = probe ? host.getComputedStyle(probe) : null;
    ["top", "right", "bottom", "left"].forEach(function (side) {
      root.style.setProperty("--safe-" + side, (style && style.getPropertyValue("padding-" + side)) || "0px");
    });
  }
  function keyboard() {
    root.toggleAttribute("data-keyboard", !!viewport && host.innerHeight - viewport.height > 120);
  }
  function attach() {
    host.addEventListener("resize", insets);
    if (viewport) viewport.addEventListener("resize", keyboard);
  }
  if (host) {
    insets();
    attach();
    window.addEventListener("pageshow", attach);
    window.addEventListener("pagehide", function () {
      host.removeEventListener("resize", insets);
      if (viewport) viewport.removeEventListener("resize", keyboard);
    });
  }
  var Native = host && "Notification" in host ? host.Notification : null;
  if (Native) {
    var icon = new URL("icons/Icon-192.png", host.document.baseURI).href;
    var Reminder = function (title, options) {
      var text = String(title || "");
      var body = options && options.body ? String(options.body) : "";
      var shown = "serviceWorker" in navigator
        ? navigator.serviceWorker.ready.then(function (registration) { return registration.showNotification(text, { body: body, icon: icon }); })
        : Promise.reject(new Error("no worker"));
      shown.catch(function () {
        try { new Native(text, { body: body, icon: icon }); } catch (error) {}
      });
    };
    Object.defineProperty(Reminder, "permission", { get: function () { return Native.permission; } });
    Reminder.requestPermission = function (callback) {
      var asked = new Promise(function (resolve) {
        var result = Native.requestPermission(resolve);
        if (result && typeof result.then === "function") result.then(resolve, function () { resolve(Native.permission); });
      });
      if (typeof callback === "function") asked.then(callback);
      return asked;
    };
    window.Notification = Reminder;
  } else if ("Notification" in window) {
    try { delete window.Notification; } catch (error) {}
  }
  function theme() {
    send("theme", root.dataset.theme === "dark" ? "dark" : "light");
  }
  new MutationObserver(theme).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
  document.addEventListener("DOMContentLoaded", function () {
    theme();
    send("ready", location.pathname);
  });
  window.addEventListener("click", function (event) {
    var link = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    if (!link || event.defaultPrevented || link.hasAttribute("download")) return;
    var url;
    try { url = new URL(link.getAttribute("href"), location.href); } catch (error) { return; }
    if (url.origin === location.origin) return;
    var mail = url.protocol === "mailto:" || url.protocol === "tel:";
    if (!mail && url.protocol !== "http:" && url.protocol !== "https:") return;
    event.preventDefault();
    if (mail) (host || window).location.href = url.href;
    else window.open(url.href, "_blank", "noopener");
  });
})();
''';
