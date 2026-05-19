(function() {
  'use strict';

  var modal = document.getElementById('search-modal');
  var input = document.getElementById('search-input');
  var results = document.getElementById('search-results');
  var trigger = document.getElementById('search-trigger');
  var searchData = null;
  var activeIndex = -1;

  function getBaseUrl() {
    var el = document.querySelector('link[rel="manifest"]');
    if (el) {
      var href = el.getAttribute('href');
      return href.replace('/site.webmanifest', '');
    }
    return '';
  }

  var baseUrl = getBaseUrl();

  function getCurrentLang() {
    var path = window.location.pathname;
    if (path.startsWith(baseUrl + '/ko/') || path === baseUrl + '/ko') {
      return 'ko';
    }
    return 'en';
  }

  function matchesCurrentLang(item) {
    var url = item.url || item.permalink || '';
    var lang = getCurrentLang();
    if (lang === 'ko') {
      return url.startsWith('/ko/') || url.startsWith(baseUrl + '/ko/');
    }
    return !url.startsWith('/ko/') && !url.startsWith(baseUrl + '/ko/');
  }

  function loadSearchData() {
    if (searchData) return Promise.resolve(searchData);
    return fetch(baseUrl + '/search.json')
      .then(function(r) { return r.json(); })
      .then(function(data) { searchData = data; return data; });
  }

  function openModal() {
    modal.classList.add('active');
    input.value = '';
    results.innerHTML = '';
    activeIndex = -1;
    setTimeout(function() { input.focus(); }, 50);
    loadSearchData();
  }

  function closeModal() {
    modal.classList.remove('active');
    input.value = '';
    results.innerHTML = '';
  }

  function fuzzyMatch(query, text) {
    if (!text) return false;
    var lower = text.toLowerCase();
    var q = query.toLowerCase();
    return lower.indexOf(q) !== -1;
  }

  function search(query) {
    if (!searchData || !query || query.length < 2) {
      results.innerHTML = '';
      return;
    }

    var matches = [];
    for (var i = 0; i < searchData.length && matches.length < 10; i++) {
      var item = searchData[i];
      if (!matchesCurrentLang(item)) continue;
      if (fuzzyMatch(query, item.title) || fuzzyMatch(query, item.content)) {
        matches.push(item);
      }
    }

    if (matches.length === 0) {
      results.innerHTML = '<div class="search-no-results">No results found</div>';
      return;
    }

    var html = '';
    for (var j = 0; j < matches.length; j++) {
      var m = matches[j];
      var snippet = '';
      if (m.content) {
        var idx = m.content.toLowerCase().indexOf(query.toLowerCase());
        if (idx !== -1) {
          var start = Math.max(0, idx - 40);
          var end = Math.min(m.content.length, idx + query.length + 60);
          snippet = (start > 0 ? '...' : '') + m.content.substring(start, end) + (end < m.content.length ? '...' : '');
        } else {
          snippet = m.content.substring(0, 100) + '...';
        }
      }
      var url = m.url || m.permalink || '#';
      html += '<a class="search-result-item" href="' + url + '">' +
        '<div class="search-result-title">' + escapeHtml(m.title || 'Untitled') + '</div>' +
        (snippet ? '<div class="search-result-snippet">' + escapeHtml(snippet) + '</div>' : '') +
        '</a>';
    }
    results.innerHTML = html;
    activeIndex = -1;
  }

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(text));
    return div.innerHTML;
  }

  function navigateResults(dir) {
    var items = results.querySelectorAll('.search-result-item');
    if (items.length === 0) return;
    activeIndex = Math.max(-1, Math.min(items.length - 1, activeIndex + dir));
    for (var i = 0; i < items.length; i++) {
      items[i].classList.toggle('active', i === activeIndex);
    }
    if (activeIndex >= 0) {
      items[activeIndex].scrollIntoView({ block: 'nearest' });
    }
  }

  // Event listeners
  if (trigger) trigger.addEventListener('click', openModal);

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      if (modal.classList.contains('active')) closeModal();
      else openModal();
    }
    if (e.key === 'Escape' && modal.classList.contains('active')) {
      closeModal();
    }
  });

  if (modal) {
    modal.querySelector('.search-modal-overlay').addEventListener('click', closeModal);
  }

  if (input) {
    var debounceTimer;
    input.addEventListener('input', function() {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function() {
        search(input.value.trim());
      }, 150);
    });

    input.addEventListener('keydown', function(e) {
      if (e.key === 'ArrowDown') { e.preventDefault(); navigateResults(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); navigateResults(-1); }
      else if (e.key === 'Enter') {
        e.preventDefault();
        var items = results.querySelectorAll('.search-result-item');
        if (activeIndex >= 0 && items[activeIndex]) {
          window.location.href = items[activeIndex].getAttribute('href');
        } else if (items.length > 0) {
          window.location.href = items[0].getAttribute('href');
        }
      }
    });
  }
})();
