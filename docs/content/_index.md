+++
title = "OWASP Noir"
description = "Hunt every endpoint in your code. Noir statically analyses source across 23 languages and 144 frameworks, exposing shadow APIs and mapping the attack surface."
template = "landing"
+++

<!-- CommonMark ends an HTML block at the first blank line. The next line, if it
     is indented 4+ spaces, then becomes an indented code block. So: no blank
     lines inside a <section>. Separate sections with a blank line only, and
     start each one at column zero. -->

<section class="hero">
  <div class="hero-sentinel" aria-hidden="true"></div>
  <div class="hero-media">
    <picture>
      <source srcset="./images/noir-wallpaper.webp" type="image/webp">
      <img class="hero-art" src="./images/noir-wallpaper.jpg"
           alt="A deserted city street at night, shot in monochrome, with the OWASP Noir wordmark lit across it."
           width="1168" height="784" fetchpriority="high" decoding="async">
    </picture>
    <div class="hero-scrim" aria-hidden="true"></div>
  </div>
  <div class="hero-inner">
    <div class="hero-copy">
      <h1>Hunt every endpoint in your code.</h1>
      <p class="hero-sub">Noir reads your source and returns the routes, parameters, and headers an attacker can reach.</p>
      <div class="hero-actions">
        <a class="btn btn-primary" href="./get_started/overview/">
          Get Started
          <svg class="ic" aria-hidden="true"><use href="#i-arrow-right"/></svg>
        </a>
        <a class="btn btn-ghost" href="https://github.com/owasp-noir/noir" target="_blank" rel="noopener noreferrer">
          <svg class="ic" aria-hidden="true"><use href="#i-brand-github"/></svg>
          GitHub
        </a>
      </div>
    </div>
  </div>
</section>

<section class="logowall">
  <h2 class="sr-only">Built with</h2>
  <div class="wrap logowall-inner">
    <a href="https://owasp.org/www-project-noir/" target="_blank" rel="noopener noreferrer">
      <img src="./images/owasp.webp" alt="OWASP" width="500" height="174" loading="lazy" decoding="async">
    </a>
    <a href="https://crystal-lang.org/" target="_blank" rel="noopener noreferrer">
      <img src="./images/crystal.webp" alt="Crystal" width="500" height="174" loading="lazy" decoding="async">
    </a>
    <a href="https://hwaro.hahwul.com/" target="_blank" rel="noopener noreferrer">
      <img src="./images/hwaro-wide.webp" alt="Hwaro" width="1316" height="483" loading="lazy" decoding="async">
    </a>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">What it does</h2>
    <p class="section-lede">One pass over your source produces the endpoint inventory that reviewers, models, and scanners all need.</p>
  </header>
  <div class="bento">
    <article class="cell cell-a" data-reveal>
      <div class="cell-body">
        <h3>Endpoint extraction</h3>
        <p>Static analysis pulls routes, methods, parameters, headers, and cookies out of the code. Shadow APIs and forgotten handlers surface in the same pass, not a separate mode.</p>
      </div>
      <div class="cell-shot">
        <img src="./images/landing/bento-endpoints.webp" alt="Noir output listing the HTTP methods, paths, headers, and idor tags it extracted from a codebase, beside the source tree it read." width="1420" height="564" loading="lazy" decoding="async">
      </div>
    </article>
    <article class="cell cell-b" data-reveal style="--reveal-delay: 70ms">
      <div class="cell-body">
        <h3>Context for AI reviewers</h3>
        <p><code>--ai-context</code> attaches guards, sinks, validators, and signals to each endpoint, so a model reads the handler instead of the whole repository.</p>
      </div>
      <div class="cell-shot">
        <img src="./images/landing/bento-aicontext.webp" alt="Per-endpoint AI context: the route definition, the detected framework, and the signals a reviewer should check." width="790" height="530" loading="lazy" decoding="async">
      </div>
    </article>
    <article class="cell cell-c" data-reveal>
      <div class="cell-body">
        <h3>Every mainstream stack</h3>
        <p>One binary, no plugins and no per-language setup. Frameworks the static rules miss fall back to an LLM.</p>
        <div class="stat-row">
          <span><span class="stat-val">23</span><span class="stat-key">Languages</span></span>
          <span><span class="stat-val">144</span><span class="stat-key">Frameworks</span></span>
        </div>
      </div>
    </article>
    <article class="cell cell-d cell-plate" data-reveal style="--reveal-delay: 70ms">
      <div class="cell-body">
        <h3>Passive scanning</h3>
        <p>Severity-graded rules run over the same tree and report hardcoded keys, tokens, and credentials. Bring your own rules or use the community set.</p>
      </div>
    </article>
    <article class="cell cell-e" data-reveal style="--reveal-delay: 140ms">
      <div class="cell-body">
        <h3>Semantic tags</h3>
        <p>Seventeen taggers annotate endpoints with the properties that decide where you look first.</p>
        <div class="tag-cloud">
          <code>cors</code><code>jwt</code><code>oauth</code><code>graphql</code><code>pii</code><code>payment</code><code>file_upload</code><code>webhook</code><code>websocket</code><code>soap</code><code>crypto</code><code>debug</code><code>admin</code><code>account_recovery</code><code>api_docs</code><code>hunt_param</code><code>mcp</code>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">How it runs</h2>
  </header>
  <div class="flow">
    <div class="flow-step" data-reveal>
      <h3>Point it at a codebase</h3>
      <p>Noir detects the language, the framework, and the routing convention on its own. There is nothing to configure first.</p>
      <code class="flow-cmd">noir scan ./your-project</code>
    </div>
    <div class="flow-step" data-reveal>
      <h3>Read what it found</h3>
      <p>Every endpoint carries the file and line it came from, so a finding is one click away from the code that produced it.</p>
      <code class="flow-cmd">noir scan ./your-project --include path,techs -f json -o endpoints.json</code>
    </div>
    <div class="flow-step" data-reveal>
      <h3>Hand it to the next tool</h3>
      <p>Export OpenAPI for a scanner, SARIF for your code-scanning dashboard, or route probes straight through an intercepting proxy.</p>
      <code class="flow-cmd">noir scan ./your-project -f oas3 --probe-via http://127.0.0.1:8080</code>
    </div>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">Output formats</h2>
    <p class="section-lede">Twenty-two of them. Pick the one your next tool already speaks.</p>
  </header>
  <div data-reveal>
    <div class="marquee">
      <div class="marquee-track">
        <code class="fmt">plain</code><code class="fmt">json</code><code class="fmt">jsonl</code><code class="fmt">yaml</code><code class="fmt">toml</code><code class="fmt">markdown-table</code><code class="fmt">sarif</code><code class="fmt">html</code><code class="fmt">oas2</code><code class="fmt">oas3</code><code class="fmt">postman</code>
        <code class="fmt" aria-hidden="true">plain</code><code class="fmt" aria-hidden="true">json</code><code class="fmt" aria-hidden="true">jsonl</code><code class="fmt" aria-hidden="true">yaml</code><code class="fmt" aria-hidden="true">toml</code><code class="fmt" aria-hidden="true">markdown-table</code><code class="fmt" aria-hidden="true">sarif</code><code class="fmt" aria-hidden="true">html</code><code class="fmt" aria-hidden="true">oas2</code><code class="fmt" aria-hidden="true">oas3</code><code class="fmt" aria-hidden="true">postman</code>
      </div>
    </div>
    <div class="marquee marquee--reverse">
      <div class="marquee-track">
        <code class="fmt">curl</code><code class="fmt">httpie</code><code class="fmt">powershell</code><code class="fmt">adb</code><code class="fmt">simctl</code><code class="fmt">mermaid</code><code class="fmt">only-url</code><code class="fmt">only-param</code><code class="fmt">only-header</code><code class="fmt">only-cookie</code><code class="fmt">only-tag</code>
        <code class="fmt" aria-hidden="true">curl</code><code class="fmt" aria-hidden="true">httpie</code><code class="fmt" aria-hidden="true">powershell</code><code class="fmt" aria-hidden="true">adb</code><code class="fmt" aria-hidden="true">simctl</code><code class="fmt" aria-hidden="true">mermaid</code><code class="fmt" aria-hidden="true">only-url</code><code class="fmt" aria-hidden="true">only-param</code><code class="fmt" aria-hidden="true">only-header</code><code class="fmt" aria-hidden="true">only-cookie</code><code class="fmt" aria-hidden="true">only-tag</code>
      </div>
    </div>
  </div>
</section>

<section class="section wrap">
  <div class="split">
    <div data-reveal>
      <h2 class="section-title">One inventory, three readers</h2>
      <div class="split-list">
        <div class="split-item">
          <h3>Security reviewers</h3>
          <p>A focused list of attacker-reachable entrypoints instead of a repository to skim.</p>
        </div>
        <div class="split-item">
          <h3>AI code auditors</h3>
          <p>The same list, plus the guards, sinks, and validators around each endpoint.</p>
        </div>
        <div class="split-item">
          <h3>DAST scanners</h3>
          <p>Routes a crawler would never reach, handed to ZAP, Burp, or Caido as a proxy target or an OpenAPI import.</p>
        </div>
      </div>
    </div>
    <div class="split-shot" data-reveal style="--reveal-delay: 90ms">
      <img src="./images/report-dark.webp" alt="The Noir HTML report, listing discovered endpoints with their methods, parameters, and tags." width="1280" height="1080" loading="lazy" decoding="async">
    </div>
  </div>
</section>

<section class="section wrap">
  <div class="community-inner">
    <div class="poster-frame" data-reveal>
      <img src="./images/hak-poster.webp" alt="A film poster of Hak, the OWASP Noir mascot: a crane in a trench coat and goggles, standing in the rain." width="2000" height="1116" loading="lazy" decoding="async">
    </div>
    <div class="community-copy" data-reveal style="--reveal-delay: 90ms">
      <h2 class="section-title">Built in the open</h2>
      <p>Noir is an OWASP Foundation project, MIT licensed, and maintained by the people who use it. Framework support, scan rules, and output formats all arrive as contributions.</p>
      <a class="btn btn-outline" href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" target="_blank" rel="noopener noreferrer">
        Read the contributing guide
        <svg class="ic" aria-hidden="true"><use href="#i-arrow-up-right"/></svg>
      </a>
    </div>
  </div>
  <div class="contributors" data-reveal>
    <p>Thanks to everyone who has contributed.</p>
    <img src="./CONTRIBUTORS.svg" alt="Avatars of the people who have contributed to OWASP Noir." width="740" height="222" loading="lazy" decoding="async">
  </div>
</section>
