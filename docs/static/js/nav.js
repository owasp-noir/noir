/* Header state, mobile drawer, sidebar collapse.
   No scroll listeners anywhere: the header's "over the hero" state comes from
   an IntersectionObserver, not from reading scrollY on every frame. */
(function () {
  "use strict";

  var root = document.documentElement;
  var header = document.querySelector(".site-header");

  /* ---- Header over the hero -------------------------------------------- */
  /* Transparent, bone ink, only while the page sits at the very top. As soon as
     anything scrolls beneath the bar it takes its background, otherwise hero
     copy passes through it and tangles with the nav links. */
  var sentinel = document.querySelector(".hero-sentinel");
  if (header && sentinel && header.hasAttribute("data-over-hero") && "IntersectionObserver" in window) {
    var headerH = parseInt(getComputedStyle(root).getPropertyValue("--header-h"), 10) || 64;
    var heroWatcher = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) header.setAttribute("data-over-hero", "");
        else header.removeAttribute("data-over-hero");
      });
    }, { rootMargin: "-" + headerH + "px 0px 0px 0px", threshold: 0 });
    heroWatcher.observe(sentinel);
  }

  /* ---- Mobile drawer ---------------------------------------------------- */
  var toggle = document.getElementById("drawerToggle");
  var scrim = document.getElementById("drawerScrim");
  var sidebar = document.getElementById("sidebar");

  function setDrawer(open) {
    if (open) root.setAttribute("data-drawer", "open");
    else root.removeAttribute("data-drawer");
    if (toggle) toggle.setAttribute("aria-expanded", String(open));
  }

  if (toggle && sidebar) {
    setDrawer(false);
    toggle.addEventListener("click", function () {
      var open = root.getAttribute("data-drawer") !== "open";
      setDrawer(open);
      if (open) {
        var first = sidebar.querySelector("a, button");
        if (first) first.focus();
      }
    });
  }
  if (scrim) scrim.addEventListener("click", function () { setDrawer(false); });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && root.getAttribute("data-drawer") === "open") {
      setDrawer(false);
      if (toggle) toggle.focus();
    }
  });

  /* ---- Sidebar collapse -------------------------------------------------- */
  function wireCollapse(buttonSelector, groupSelector) {
    document.querySelectorAll(buttonSelector).forEach(function (btn) {
      var group = btn.closest(groupSelector);
      if (!group) return;
      btn.addEventListener("click", function () {
        var collapsed = group.hasAttribute("data-collapsed");
        if (collapsed) group.removeAttribute("data-collapsed");
        else group.setAttribute("data-collapsed", "");
        btn.setAttribute("aria-expanded", String(collapsed));
      });
    });
  }
  wireCollapse(".sidebar-heading", ".sidebar-group");
  wireCollapse(".sidebar-subheading", ".sidebar-subgroup");

  /* Which branch starts open is decided server-side in sidebar.html, so the tree
     never renders fully expanded and then snaps shut. Nothing to do here but
     bring the current page into view when the open branch is taller than the
     rail. */
  var current = document.querySelector('.docs-sidebar a[aria-current="page"]');
  if (current && sidebar && current.offsetTop > sidebar.clientHeight) {
    sidebar.scrollTop = current.offsetTop - sidebar.clientHeight / 2;
  }
})();
