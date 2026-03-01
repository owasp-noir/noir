(function() {
  'use strict';

  var LANG_DISPLAY = {
    'bash': 'Bash',
    'sh': 'Shell',
    'shell': 'Shell',
    'zsh': 'Zsh',
    'crystal': 'Crystal',
    'cr': 'Crystal',
    'ruby': 'Ruby',
    'rb': 'Ruby',
    'python': 'Python',
    'py': 'Python',
    'javascript': 'JavaScript',
    'js': 'JavaScript',
    'typescript': 'TypeScript',
    'ts': 'TypeScript',
    'json': 'JSON',
    'yaml': 'YAML',
    'yml': 'YAML',
    'toml': 'TOML',
    'html': 'HTML',
    'css': 'CSS',
    'xml': 'XML',
    'sql': 'SQL',
    'go': 'Go',
    'golang': 'Go',
    'rust': 'Rust',
    'rs': 'Rust',
    'java': 'Java',
    'kotlin': 'Kotlin',
    'kt': 'Kotlin',
    'swift': 'Swift',
    'c': 'C',
    'cpp': 'C++',
    'csharp': 'C#',
    'cs': 'C#',
    'php': 'PHP',
    'docker': 'Dockerfile',
    'dockerfile': 'Dockerfile',
    'makefile': 'Makefile',
    'markdown': 'Markdown',
    'md': 'Markdown',
    'diff': 'Diff',
    'plaintext': 'Text',
    'text': 'Text',
    'txt': 'Text',
    'lua': 'Lua',
    'perl': 'Perl',
    'r': 'R',
    'scala': 'Scala',
    'elixir': 'Elixir',
    'ex': 'Elixir',
    'erlang': 'Erlang',
    'haskell': 'Haskell',
    'hs': 'Haskell',
    'nginx': 'Nginx',
    'apache': 'Apache',
    'graphql': 'GraphQL',
    'proto': 'Protobuf',
    'protobuf': 'Protobuf',
    'ini': 'INI',
    'env': '.env',
    'jinja': 'Jinja2',
    'jinja2': 'Jinja2'
  };

  var COPY_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
  var CHECK_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

  function detectLanguage(codeEl) {
    var classes = codeEl.className || '';
    var match = classes.match(/(?:language|lang)-(\w+)/);
    if (match) return match[1].toLowerCase();
    return '';
  }

  function getDisplayName(lang) {
    if (!lang) return '';
    return LANG_DISPLAY[lang] || lang.charAt(0).toUpperCase() + lang.slice(1);
  }

  function copyToClipboard(text, btn) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function() {
        showCopied(btn);
      }, function() {
        fallbackCopy(text, btn);
      });
    } else {
      fallbackCopy(text, btn);
    }
  }

  function fallbackCopy(text, btn) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      showCopied(btn);
    } catch (e) {
      // silently fail
    }
    document.body.removeChild(textarea);
  }

  function showCopied(btn) {
    btn.innerHTML = CHECK_ICON + '<span>Copied!</span>';
    btn.classList.add('copied');
    setTimeout(function() {
      btn.innerHTML = COPY_ICON + '<span>Copy</span>';
      btn.classList.remove('copied');
    }, 2000);
  }

  function enhanceCodeBlocks() {
    var preBlocks = document.querySelectorAll('.docs-article pre');

    for (var i = 0; i < preBlocks.length; i++) {
      var pre = preBlocks[i];

      // Skip if already enhanced
      if (pre.parentElement && pre.parentElement.classList.contains('codeblock')) continue;

      var code = pre.querySelector('code');
      if (!code) continue;

      var lang = detectLanguage(code);
      var displayName = getDisplayName(lang);

      // Create wrapper
      var wrapper = document.createElement('div');
      wrapper.className = 'codeblock';
      if (lang) wrapper.setAttribute('data-lang', lang);

      // Create header bar
      var header = document.createElement('div');
      header.className = 'codeblock-header';

      // Left side: dots
      var dots = document.createElement('div');
      dots.className = 'codeblock-dots';
      dots.innerHTML = '<span></span><span></span><span></span>';

      // Center: language label
      var label = document.createElement('div');
      label.className = 'codeblock-lang';
      label.textContent = displayName;

      // Right side: copy button
      var copyBtn = document.createElement('button');
      copyBtn.className = 'codeblock-copy';
      copyBtn.type = 'button';
      copyBtn.setAttribute('aria-label', 'Copy code');
      copyBtn.innerHTML = COPY_ICON + '<span>Copy</span>';

      // Bind copy event (use closure for correct pre reference)
      (function(preRef, btnRef) {
        btnRef.addEventListener('click', function() {
          var codeEl = preRef.querySelector('code');
          var text = codeEl ? codeEl.textContent : preRef.textContent;
          copyToClipboard(text, btnRef);
        });
      })(pre, copyBtn);

      header.appendChild(dots);
      header.appendChild(label);
      header.appendChild(copyBtn);

      // Wrap the pre element
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(header);
      wrapper.appendChild(pre);
    }
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', enhanceCodeBlocks);
  } else {
    enhanceCodeBlocks();
  }
})();
