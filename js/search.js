/* Search modal. Reads the fuse_json index hwaro emits at <base>/search.json,
   whose entries are { title, content, url, lang }. */
(function () {
  "use strict";

  var overlay = document.getElementById("searchOverlay");
  var input = document.getElementById("searchInput");
  var results = document.getElementById("searchResults");
  var trigger = document.getElementById("searchTrigger");
  var closeBtn = document.getElementById("searchClose");
  if (!overlay || !input || !results) return;

  var data = null;
  var loading = false;
  var active = -1;
  var lastFocus = null;

  var base = (window.NOIR_BASE || "").replace(/\/+$/, "");
  var T = window.NOIR_I18N || {};

  /* Path component of base_url — "/noir" for https://owasp-noir.github.io/noir,
     "" for the bare host `hwaro serve` hands out. hwaro bakes this prefix into
     the urls it writes to search.json, so results are already root-absolute and
     ready to use; prepending base again produced /noir/noir/… 404s in
     production while staying invisible on a path-less local server. The prefix
     is only added when an entry is genuinely missing it. */
  var basePath = base.replace(/^[a-z][a-z0-9+.-]*:\/\/[^\/]*/i, "").replace(/\/+$/, "");

  function resolve(url) {
    if (!url) return "#";
    if (url.charAt(0) !== "/" || !basePath) return url;
    if (url === basePath || url.indexOf(basePath + "/") === 0) return url;
    return basePath + url;
  }

  function load() {
    if (data || loading) return Promise.resolve(data || []);
    loading = true;
    return fetch(base + "/search.json")
      .then(function (r) { return r.json(); })
      .then(function (json) { data = json; return data; })
      .catch(function () { data = []; return data; });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function mark(text, query) {
    var out = escapeHtml(text);
    if (!query) return out;
    return out.replace(new RegExp("(" + escapeRe(escapeHtml(query)) + ")", "gi"), "<mark>$1</mark>");
  }

  function snippet(content, query) {
    var body = String(content || "").replace(/\s+/g, " ").trim();
    var i = body.toLowerCase().indexOf(query.toLowerCase());
    if (i === -1) return body.slice(0, 160);
    var start = Math.max(0, i - 60);
    var end = Math.min(body.length, i + query.length + 110);
    return (start > 0 ? "…" : "") + body.slice(start, end).trim() + (end < body.length ? "…" : "");
  }

  function render(query) {
    var q = query.trim();
    if (!data || !q) { results.innerHTML = ""; active = -1; return; }

    var lang = document.documentElement.lang || "";
    var ql = q.toLowerCase();
    var hits = [];

    for (var i = 0; i < data.length; i++) {
      var item = data[i];
      if (lang && item.lang && item.lang !== lang) continue;
      var ti = String(item.title || "").toLowerCase().indexOf(ql);
      var ci = String(item.content || "").toLowerCase().indexOf(ql);
      if (ti === -1 && ci === -1) continue;
      hits.push({ item: item, score: ti !== -1 ? 1000 - ti : 500 - Math.min(ci, 400) });
    }

    hits.sort(function (a, b) { return b.score - a.score; });
    hits = hits.slice(0, 8);

    if (!hits.length) {
      results.innerHTML = '<p class="search-empty">' + escapeHtml(T.noResults || "No results for") + ' "' + escapeHtml(q) + '"</p>';
      active = -1;
      return;
    }

    results.innerHTML = hits.map(function (h, n) {
      var url = resolve(h.item.url || h.item.permalink);
      return '<a class="search-result" role="option" aria-selected="false" data-i="' + n + '" href="' + escapeHtml(url) + '">' +
        "<strong>" + mark(h.item.title || "Untitled", q) + "</strong>" +
        "<span>" + mark(snippet(h.item.content, q), q) + "</span>" +
        "</a>";
    }).join("");
    active = -1;
  }

  function items() { return results.querySelectorAll(".search-result"); }

  function move(delta) {
    var list = items();
    if (!list.length) return;
    active = (active + delta + list.length) % list.length;
    for (var i = 0; i < list.length; i++) {
      var on = i === active;
      list[i].classList.toggle("is-active", on);
      list[i].setAttribute("aria-selected", String(on));
      if (on) list[i].scrollIntoView({ block: "nearest" });
    }
  }

  function open() {
    lastFocus = document.activeElement;
    overlay.hidden = false;
    overlay.classList.add("is-open");
    input.value = "";
    results.innerHTML = "";
    active = -1;
    input.focus();
    load();
  }

  function close() {
    overlay.classList.remove("is-open");
    overlay.hidden = true;
    active = -1;
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function isOpen() { return overlay.classList.contains("is-open"); }

  if (trigger) trigger.addEventListener("click", open);
  if (closeBtn) {
    closeBtn.addEventListener("click", close);
    closeBtn.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); close(); }
    });
  }

  overlay.addEventListener("click", function (e) { if (e.target === overlay) close(); });

  input.addEventListener("input", function () {
    load().then(function () { render(input.value); });
  });

  input.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown") { e.preventDefault(); move(1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); move(-1); }
    else if (e.key === "Enter") {
      var list = items();
      if (!list.length) return;
      e.preventDefault();
      (list[active >= 0 ? active : 0]).click();
    }
  });

  document.addEventListener("keydown", function (e) {
    if ((e.metaKey || e.ctrlKey) && (e.key === "k" || e.key === "K")) {
      e.preventDefault();
      isOpen() ? close() : open();
    } else if (e.key === "Escape" && isOpen()) {
      close();
    }
  });
})();
