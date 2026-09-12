/* Table-of-contents scroll-spy via IntersectionObserver.
   No scroll listener: headings report themselves as they cross a band just
   below the sticky header. */
(function () {
  "use strict";

  var toc = document.querySelector(".docs-toc");
  var prose = document.querySelector(".prose");
  if (!toc || !prose || !("IntersectionObserver" in window)) return;

  var links = {};
  toc.querySelectorAll('a[href^="#"]').forEach(function (a) {
    links[decodeURIComponent(a.getAttribute("href").slice(1))] = a;
  });

  var headings = Array.prototype.filter.call(
    prose.querySelectorAll("h2[id], h3[id]"),
    function (h) { return Object.prototype.hasOwnProperty.call(links, h.id); }
  );
  if (!headings.length) return;

  var order = {};
  headings.forEach(function (h, i) { order[h.id] = i; });

  var visible = new Set();
  var lastId = headings[0].id;

  function paint(id) {
    if (!id) return;
    Object.keys(links).forEach(function (k) { links[k].classList.remove("is-active"); });
    if (links[id]) links[id].classList.add("is-active");
  }

  var headerH = parseInt(getComputedStyle(document.documentElement).getPropertyValue("--header-h"), 10) || 64;

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) visible.add(e.target.id);
      else visible.delete(e.target.id);
    });

    if (visible.size) {
      // Topmost heading currently inside the band wins.
      var topId = null;
      visible.forEach(function (id) {
        if (topId === null || order[id] < order[topId]) topId = id;
      });
      lastId = topId;
    }
    paint(lastId);
  }, {
    rootMargin: "-" + (headerH + 4) + "px 0px -72% 0px",
    threshold: 0
  });

  headings.forEach(function (h) { io.observe(h); });
  paint(lastId);
})();
