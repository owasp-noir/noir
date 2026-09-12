/* Theme toggle: auto -> light -> dark -> auto.
   The pinned value is read back in header.html before first paint, so there is
   no flash. "auto" means: remove the attribute and let color-scheme decide,
   which resolves to dark when the visitor has no OS preference. */
(function () {
  "use strict";

  var KEY = "noir-theme";
  var MODES = ["auto", "light", "dark"];
  var root = document.documentElement;
  var btn = document.getElementById("themeToggle");
  if (!btn) return;

  var T = window.NOIR_I18N || {};
  var LABEL = {
    auto: T.themeAuto || "auto",
    light: T.themeLight || "light",
    dark: T.themeDark || "dark"
  };

  function apply(mode) {
    if (mode === "auto") {
      root.removeAttribute("data-theme");
      try { localStorage.removeItem(KEY); } catch (e) {}
    } else {
      root.setAttribute("data-theme", mode);
      try { localStorage.setItem(KEY, mode); } catch (e) {}
    }
    btn.setAttribute("data-mode", mode);
    var text = (T.theme || "Theme") + ": " + LABEL[mode];
    btn.setAttribute("aria-label", text);
    btn.title = text;
  }

  var stored = "auto";
  try {
    var t = localStorage.getItem(KEY);
    if (t === "light" || t === "dark") stored = t;
  } catch (e) {}

  apply(stored);

  btn.addEventListener("click", function () {
    var next = MODES[(MODES.indexOf(btn.getAttribute("data-mode")) + 1) % MODES.length];
    apply(next);
  });
})();
