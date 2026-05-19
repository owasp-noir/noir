(function() {
  'use strict';

  var sidebar = document.getElementById('docs-sidebar');
  var hamburger = document.getElementById('hamburger-toggle');
  var overlay = document.getElementById('site-overlay');
  var currentPath = window.location.pathname;

  // Normalize path: ensure trailing slash
  if (currentPath.length > 1 && !currentPath.endsWith('/')) {
    currentPath += '/';
  }

  // Set active link and expand parent sections
  var links = sidebar ? sidebar.querySelectorAll('a[href]') : [];
  for (var i = 0; i < links.length; i++) {
    var link = links[i];
    var href = link.getAttribute('href');
    if (href && !href.endsWith('/')) href += '/';

    if (href && currentPath.endsWith(href.replace(/^.*\/\/[^\/]+/, ''))) {
      link.classList.add('active');

      // Expand parent subsection
      var subsection = link.closest('.sidebar-subsection');
      if (subsection) {
        subsection.classList.add('expanded');
      }

      // Expand parent section
      var section = link.closest('.sidebar-section');
      if (section) {
        section.classList.add('expanded');
      }
    }
  }

  // Collapsible sections
  var headings = sidebar ? sidebar.querySelectorAll('.sidebar-heading') : [];
  for (var j = 0; j < headings.length; j++) {
    headings[j].addEventListener('click', function() {
      var section = this.parentElement;
      section.classList.toggle('expanded');
    });
  }

  // Collapsible subsections
  var subheadings = sidebar ? sidebar.querySelectorAll('.sidebar-subheading') : [];
  for (var k = 0; k < subheadings.length; k++) {
    subheadings[k].addEventListener('click', function() {
      var subsection = this.parentElement;
      subsection.classList.toggle('expanded');
    });
  }

  // If no section is expanded (e.g., landing page), expand the first one
  if (sidebar) {
    var expanded = sidebar.querySelector('.sidebar-section.expanded');
    if (!expanded) {
      var first = sidebar.querySelector('.sidebar-section');
      if (first) first.classList.add('expanded');
    }
  }

  // Mobile toggle
  function toggleSidebar() {
    if (sidebar) sidebar.classList.toggle('open');
    if (overlay) overlay.classList.toggle('active');
  }

  function closeSidebar() {
    if (sidebar) sidebar.classList.remove('open');
    if (overlay) overlay.classList.remove('active');
  }

  if (hamburger) hamburger.addEventListener('click', toggleSidebar);
  if (overlay) overlay.addEventListener('click', closeSidebar);

  // Close sidebar on link click (mobile)
  if (sidebar) {
    var navLinks = sidebar.querySelectorAll('a[href]');
    for (var m = 0; m < navLinks.length; m++) {
      navLinks[m].addEventListener('click', function() {
        if (window.innerWidth <= 768) closeSidebar();
      });
    }
  }
})();
