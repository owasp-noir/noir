/* Mermaid diagrams, themed from the live palette and re-rendered when the
   visitor flips the theme. The old shortcode hardcoded `theme: "dark"`, which
   rendered black-on-black once light mode existed.

   The renderer is fetched from jsdelivr, the same CDN the current site uses,
   and only on pages that contain a diagram. */
(function () {
  "use strict";

  var nodes = document.querySelectorAll("pre.mermaid");
  if (!nodes.length) return;

  // Keep the source: mermaid replaces the element's contents with an SVG.
  var sources = [];
  nodes.forEach(function (n) { sources.push(n.textContent); });

  /* Custom properties declared with light-dark() do not resolve when read off
     :root, so probe a real element for the computed colors instead. */
  function resolve(cssValue) {
    var probe = document.createElement("span");
    probe.style.cssText = "position:absolute;visibility:hidden;color:" + cssValue;
    document.body.appendChild(probe);
    var out = getComputedStyle(probe).color;
    probe.remove();
    return out;
  }

  function palette() {
    var body = getComputedStyle(document.body);
    return {
      background: body.backgroundColor,
      primaryColor: resolve("var(--surface)"),
      primaryTextColor: resolve("var(--heading)"),
      primaryBorderColor: resolve("var(--border)"),
      secondaryColor: resolve("var(--bg-subtle)"),
      secondaryTextColor: resolve("var(--text)"),
      secondaryBorderColor: resolve("var(--border)"),
      tertiaryColor: resolve("var(--bg-subtle)"),
      tertiaryTextColor: resolve("var(--text)"),
      tertiaryBorderColor: resolve("var(--border-subtle)"),
      lineColor: resolve("var(--text-muted)"),
      textColor: body.color,
      mainBkg: resolve("var(--surface)"),
      nodeBorder: resolve("var(--border)"),
      clusterBkg: resolve("var(--bg-subtle)"),
      clusterBorder: resolve("var(--border-subtle)"),
      titleColor: resolve("var(--heading)"),
      edgeLabelBackground: resolve("var(--bg)"),
      fontFamily: getComputedStyle(document.documentElement).getPropertyValue("--font-sans") || "sans-serif"
    };
  }

  function render() {
    if (!window.mermaid) return;
    nodes.forEach(function (n, i) {
      n.removeAttribute("data-processed");
      n.textContent = sources[i];
    });
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      themeVariables: palette()
    });
    window.mermaid.run({ nodes: Array.prototype.slice.call(nodes) });
  }

  /* Pinned to an exact version with a subresource integrity hash. A floating
     `mermaid@10` tag resolves to whatever the newest 10.x happens to be, which
     means a third party can change the script this site executes. Bump both
     values together:
       curl -sfL <url> | openssl dgst -sha384 -binary | openssl base64 -A */
  var script = document.createElement("script");
  script.src = "https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js";
  script.integrity = "sha384-WmdflGW9aGfoBdHc4rRyWzYuAjEmDwMdGdiPNacbwfGKxBW/SO6guzuQ76qjnSlr";
  script.crossOrigin = "anonymous";
  script.referrerPolicy = "no-referrer";
  script.onload = function () {
    render();

    // Re-render on an explicit toggle...
    new MutationObserver(render).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"]
    });
    // ...and on an OS-level change while the toggle sits at "auto".
    var mq = window.matchMedia("(prefers-color-scheme: light)");
    var onChange = function () {
      if (!document.documentElement.hasAttribute("data-theme")) render();
    };
    if (mq.addEventListener) mq.addEventListener("change", onChange);
    else if (mq.addListener) mq.addListener(onChange);
  };
  script.onerror = function () {
    // Leave the source text visible rather than an empty box.
    nodes.forEach(function (n) { n.classList.add("mermaid-failed"); });
  };
  document.head.appendChild(script);
})();
