(function() {
  'use strict';

  var article = document.querySelector('.docs-article');
  var tocNav = document.getElementById('toc-nav');
  if (!article || !tocNav) return;

  var headings = article.querySelectorAll('h2, h3');
  if (headings.length === 0) {
    var tocEl = document.getElementById('docs-toc');
    if (tocEl) tocEl.style.display = 'none';
    return;
  }

  // Generate TOC
  var fragment = document.createDocumentFragment();
  for (var i = 0; i < headings.length; i++) {
    var heading = headings[i];
    if (!heading.id) {
      heading.id = heading.textContent.trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/(^-|-$)/g, '');
    }
    var a = document.createElement('a');
    a.href = '#' + heading.id;
    a.textContent = heading.textContent;
    if (heading.tagName === 'H3') a.className = 'toc-h3';
    a.setAttribute('data-heading-id', heading.id);
    fragment.appendChild(a);
  }
  tocNav.appendChild(fragment);

  // Scroll tracking with IntersectionObserver
  if ('IntersectionObserver' in window) {
    var tocLinks = tocNav.querySelectorAll('a');
    var observer = new IntersectionObserver(function(entries) {
      for (var j = 0; j < entries.length; j++) {
        if (entries[j].isIntersecting) {
          var id = entries[j].target.id;
          for (var k = 0; k < tocLinks.length; k++) {
            tocLinks[k].classList.toggle('active',
              tocLinks[k].getAttribute('data-heading-id') === id);
          }
          break;
        }
      }
    }, {
      rootMargin: '-' + (parseInt(getComputedStyle(document.documentElement).getPropertyValue('--header-h')) + 20) + 'px 0px -70% 0px',
      threshold: 0
    });

    for (var m = 0; m < headings.length; m++) {
      observer.observe(headings[m]);
    }
  }
})();
