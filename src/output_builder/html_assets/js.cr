# Client-side scripts for the self-contained HTML report.
module HtmlReportAssets
  # Applies persisted theme/view/group preferences before first paint
  # so the page never flashes the wrong state.
  THEME_BOOT = <<-JS
    (function () {
      try {
        var saved = localStorage.getItem("noir-theme");
        if (saved === "dark" || saved === "light") {
          document.documentElement.setAttribute("data-theme", saved);
        } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
          document.documentElement.setAttribute("data-theme", "dark");
        }
        if (localStorage.getItem("noir-view") === "table") {
          document.documentElement.setAttribute("data-view", "table");
        }
        if (localStorage.getItem("noir-group") === "off") {
          document.documentElement.setAttribute("data-group", "off");
        }
      } catch (e) {}
    })();
    JS

  SCRIPTS = <<-JS
    (function () {
      var root = document.documentElement;

      function toArray(nodes) { return Array.prototype.slice.call(nodes); }

      // Reflect the active theme on the toggle control (a11y state).
      function syncThemeButtons() {
        var dark = root.getAttribute("data-theme") === "dark";
        toArray(document.querySelectorAll('[data-action="toggle-theme"]')).forEach(function (b) {
          b.setAttribute("aria-pressed", String(dark));
          b.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
        });
      }
      syncThemeButtons();

      // Theme toggle with persistence (initial theme is set in <head>).
      document.addEventListener("click", function (e) {
        var btn = e.target.closest && e.target.closest('[data-action="toggle-theme"]');
        if (!btn) return;
        var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
        root.setAttribute("data-theme", next);
        try { localStorage.setItem("noir-theme", next); } catch (err) {}
        syncThemeButtons();
      });

      // Cards <-> compact table view, persisted (initial value set in <head>).
      function syncViewButtons() {
        var mode = root.getAttribute("data-view") === "table" ? "table" : "cards";
        toArray(document.querySelectorAll('[data-action="set-view"]')).forEach(function (b) {
          b.setAttribute("aria-pressed", String(b.getAttribute("data-view-mode") === mode));
        });
      }
      syncViewButtons();

      document.addEventListener("click", function (e) {
        var btn = e.target.closest && e.target.closest('[data-action="set-view"]');
        if (!btn) return;
        var mode = btn.getAttribute("data-view-mode") === "table" ? "table" : "cards";
        if (mode === "table") { root.setAttribute("data-view", "table"); } else { root.removeAttribute("data-view"); }
        try { localStorage.setItem("noir-view", mode); } catch (err) {}
        syncViewButtons();
      });

      // Grouped <-> flat rendering of the endpoint list, persisted.
      function syncGroupButtons() {
        var on = root.getAttribute("data-group") !== "off";
        toArray(document.querySelectorAll('[data-action="toggle-group"]')).forEach(function (b) {
          b.setAttribute("aria-pressed", String(on));
        });
      }
      syncGroupButtons();

      document.addEventListener("click", function (e) {
        var btn = e.target.closest && e.target.closest('[data-action="toggle-group"]');
        if (!btn) return;
        var turningOff = root.getAttribute("data-group") !== "off";
        if (turningOff) { root.setAttribute("data-group", "off"); } else { root.removeAttribute("data-group"); }
        try { localStorage.setItem("noir-group", turningOff ? "off" : "on"); } catch (err) {}
        syncGroupButtons();
      });

      // Collapse / expand a path group.
      document.addEventListener("click", function (e) {
        var btn = e.target.closest && e.target.closest('[data-action="toggle-group-collapse"]');
        if (!btn) return;
        var group = btn.closest(".group");
        if (!group) return;
        var collapsed = group.classList.toggle("collapsed");
        btn.setAttribute("aria-expanded", String(!collapsed));
      });

      // Collapse / expand an endpoint card.
      document.addEventListener("click", function (e) {
        var header = e.target.closest && e.target.closest('[data-action="toggle-card"]');
        if (!header) return;
        var card = header.closest(".card");
        if (!card) return;
        var collapsed = card.classList.toggle("collapsed");
        header.setAttribute("aria-expanded", String(!collapsed));
      });

      // Copy URL / copy-as-curl with a fallback for file:// clipboard limits.
      var copyStatus = document.getElementById("copy-status");

      function fallbackCopy(text) {
        var ta = document.createElement("textarea");
        ta.value = text;
        ta.setAttribute("readonly", "");
        ta.style.position = "fixed";
        ta.style.left = "-9999px";
        document.body.appendChild(ta);
        ta.select();
        var ok = false;
        try { ok = document.execCommand("copy"); } catch (err) {}
        document.body.removeChild(ta);
        return ok;
      }

      function flashCopied(btn, ok, label) {
        if (!ok) return;
        btn.classList.add("copied");
        setTimeout(function () { btn.classList.remove("copied"); }, 1400);
        if (copyStatus) copyStatus.textContent = label;
      }

      function copyText(text, btn, label) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(
            function () { flashCopied(btn, true, label); },
            function () { flashCopied(btn, fallbackCopy(text), label); }
          );
        } else {
          flashCopied(btn, fallbackCopy(text), label);
        }
      }

      document.addEventListener("click", function (e) {
        var btn = e.target.closest && e.target.closest('[data-action="copy-url"], [data-action="copy-curl"]');
        if (!btn) return;
        var card = btn.closest(".card");
        if (!card) return;
        var isCurl = btn.getAttribute("data-action") === "copy-curl";
        var text = card.getAttribute(isCurl ? "data-curl" : "data-url") || "";
        if (text) copyText(text, btn, isCurl ? "Copied curl command" : "Copied URL");
      });

      // Endpoint search + HTTP-method chip filter (combined with AND).
      var search = document.getElementById("endpoint-search");
      var methodChips = toArray(document.querySelectorAll("[data-filter-method]"));
      var endpointCards = toArray(document.querySelectorAll("[data-endpoint]"));
      var endpointCount = document.getElementById("endpoint-count");
      var endpointEmpty = document.getElementById("endpoint-no-results");
      var endpointSection = endpointEmpty ? endpointEmpty.closest(".section") : null;
      var groups = toArray(document.querySelectorAll(".group[data-group-key]"));

      function applyEndpointFilter() {
        var q = (search ? search.value : "").trim().toLowerCase();
        var active = methodChips
          .filter(function (c) { return c.getAttribute("aria-pressed") === "true"; })
          .map(function (c) { return c.getAttribute("data-filter-method"); });
        var shown = 0;
        endpointCards.forEach(function (card) {
          var okText = !q || (card.getAttribute("data-text") || "").indexOf(q) !== -1;
          var okMethod = active.length === 0 || active.indexOf(card.getAttribute("data-method")) !== -1;
          var visible = okText && okMethod;
          card.hidden = !visible;
          if (visible) shown++;
        });
        groups.forEach(function (group) {
          var cards = toArray(group.querySelectorAll("[data-endpoint]"));
          var visible = cards.filter(function (c) { return !c.hidden; }).length;
          var count = group.querySelector("[data-group-count]");
          if (count) {
            count.textContent = visible === cards.length ? String(cards.length) : visible + " / " + cards.length;
          }
          group.hidden = visible === 0;
        });
        if (endpointSection) {
          endpointSection.classList.toggle("filtering", Boolean(q) || active.length > 0);
        }
        if (endpointCount) {
          endpointCount.textContent = shown === endpointCards.length ? String(shown) : shown + " / " + endpointCards.length;
        }
        if (endpointEmpty) endpointEmpty.classList.toggle("show", shown === 0);
      }

      if (search) search.addEventListener("input", applyEndpointFilter);
      methodChips.forEach(function (chip) {
        chip.addEventListener("click", function () {
          chip.setAttribute("aria-pressed", chip.getAttribute("aria-pressed") === "true" ? "false" : "true");
          applyEndpointFilter();
        });
      });

      // Passive-finding severity chip filter.
      var sevChips = toArray(document.querySelectorAll("[data-filter-severity]"));
      var passiveCards = toArray(document.querySelectorAll("[data-passive]"));
      var passiveCount = document.getElementById("passive-count");
      var passiveEmpty = document.getElementById("passive-no-results");

      function applyPassiveFilter() {
        var active = sevChips
          .filter(function (c) { return c.getAttribute("aria-pressed") === "true"; })
          .map(function (c) { return c.getAttribute("data-filter-severity"); });
        var shown = 0;
        passiveCards.forEach(function (card) {
          var visible = active.length === 0 || active.indexOf(card.getAttribute("data-severity")) !== -1;
          card.hidden = !visible;
          if (visible) shown++;
        });
        if (passiveCount) {
          passiveCount.textContent = shown === passiveCards.length ? String(shown) : shown + " / " + passiveCards.length;
        }
        if (passiveEmpty) passiveEmpty.classList.toggle("show", shown === 0);
      }

      sevChips.forEach(function (chip) {
        chip.addEventListener("click", function () {
          chip.setAttribute("aria-pressed", chip.getAttribute("aria-pressed") === "true" ? "false" : "true");
          applyPassiveFilter();
        });
      });
    })();
    JS
end
