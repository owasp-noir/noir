/* Highlight code, then give every block a language label and a copy button. */
(function () {
  "use strict";

  if (window.hljs && typeof window.hljs.highlightAll === "function") {
    window.hljs.highlightAll();
  }

  var COPY_ICON = '<svg class="ic ic-copy" aria-hidden="true"><use href="#i-copy"/></svg>';
  var CHECK_ICON = '<svg class="ic ic-check" aria-hidden="true"><use href="#i-check"/></svg>';

  function labelFor(code) {
    var match = /(?:^|\s)language-([\w+#-]+)/.exec(code.className || "");
    if (match) return match[1];
    return "code";
  }

  document.querySelectorAll(".prose pre").forEach(function (pre) {
    if (pre.parentElement && pre.parentElement.classList.contains("code-block")) return;

    var code = pre.querySelector("code");
    var wrap = document.createElement("div");
    wrap.className = "code-block";
    pre.parentNode.insertBefore(wrap, pre);

    var head = document.createElement("div");
    head.className = "code-block-head";

    var lang = document.createElement("span");
    lang.className = "code-lang";
    lang.textContent = code ? labelFor(code) : "code";

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "code-copy";
    btn.innerHTML = COPY_ICON + CHECK_ICON + '<span class="code-copy-label">Copy</span>';
    btn.setAttribute("aria-label", "Copy code to clipboard");

    /* The async Clipboard API rejects on an unfocused document and does not
       exist outside a secure context, so keep the old execCommand path as a
       fallback rather than telling the reader to copy it by hand. */
    function legacyCopy(text) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.cssText = "position:absolute;left:-9999px;top:0";
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      ta.remove();
      return ok;
    }

    var resetTimer = null;
    btn.addEventListener("click", function () {
      var text = (code || pre).innerText;
      var done = function (ok) {
        btn.querySelector(".code-copy-label").textContent = ok ? "Copied" : "Press Ctrl C";
        if (ok) btn.setAttribute("data-copied", "");
        clearTimeout(resetTimer);
        resetTimer = setTimeout(function () {
          btn.removeAttribute("data-copied");
          btn.querySelector(".code-copy-label").textContent = "Copy";
        }, 1800);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(
          function () { done(true); },
          function () { done(legacyCopy(text)); }
        );
      } else {
        done(legacyCopy(text));
      }
    });

    head.appendChild(lang);
    head.appendChild(btn);
    wrap.appendChild(head);
    wrap.appendChild(pre);
  });

  /* Anchor links on headings. */
  document.querySelectorAll(".prose h2[id], .prose h3[id], .prose h4[id]").forEach(function (h) {
    if (h.querySelector(".heading-anchor")) return;
    var a = document.createElement("a");
    a.className = "heading-anchor";
    a.href = "#" + h.id;
    a.textContent = "#";
    a.setAttribute("aria-label", "Link to this section");
    h.appendChild(a);
  });
})();
