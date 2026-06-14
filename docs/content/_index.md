+++
title = "OWASP Noir"
template = "landing"
+++

<section class="hero">
  <div class="hero-inner">
    <div class="hero-intro">
      <div class="hero-eyebrow">
        <span class="hero-badge">v1.1.0</span>
        <span class="hero-badge hero-badge-owasp">OWASP Project</span>
      </div>
      <h1 class="hero-title">
        <span class="hero-title-line">Hunt Endpoints.</span>
        <span class="hero-title-line">Expose Shadow APIs.</span>
        <span class="hero-title-line hero-title-accent">Map the Attack Surface.</span>
      </h1>
      <p class="hero-desc">Discovers endpoints, parameters, and hidden routes from source code across 50+ frameworks. The inventory goes to reviewers, AI auditors, and DAST scanners that need a real route list.</p>
      <div class="hero-actions">
        <a href="./get_started/overview" class="hero-btn hero-btn-primary">
          <span>Get Started</span>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
        </a>
        <a href="https://github.com/owasp-noir/noir" class="hero-btn hero-btn-secondary">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
          <span>GitHub</span>
        </a>
      </div>
    </div>
    <div class="hero-showcase">
      <div class="split-stage">
        <div class="split-pane split-a">
          <img src="./images/landing/1.webp" alt="Noir turns source code into a clean, human-readable endpoint inventory" width="1904" height="1162" loading="eager" decoding="async" fetchpriority="high">
          <span class="split-tag">source &rarr; endpoints</span>
        </div>
        <div class="split-pane split-b">
          <img src="./images/landing/2.webp" alt="Per-endpoint AI context: callees, guards, and security signals" width="1904" height="1162" loading="lazy" decoding="async">
          <span class="split-tag">ai context</span>
        </div>
        <span class="split-hint">hover to reveal</span>
      </div>
    </div>
  </div>
</section>

<div class="stats-bar">
  <div class="stats-inner">
    <div class="stat-item">
      <span class="stat-value">50+</span>
      <span class="stat-label">Languages & Frameworks</span>
    </div>
    <div class="stat-sep"></div>
    <div class="stat-item">
      <span class="stat-value">20+</span>
      <span class="stat-label">Output Formats</span>
    </div>
    <div class="stat-sep"></div>
    <div class="stat-item">
      <span class="stat-value">AI</span>
      <span class="stat-label">Powered Analysis</span>
    </div>
    <div class="stat-sep"></div>
    <div class="stat-item">
      <span class="stat-value">OSS</span>
      <span class="stat-label">Open Source</span>
    </div>
  </div>
</div>

<section class="features-section">
  <div class="features-inner">
    <p class="features-label">Capabilities</p>
    <h2 class="features-title">What it does</h2>
    <div class="features-grid">
      <div class="feature-cell feature-wide">
        <div class="feature-number">01</div>
        <h3>Endpoint Extraction</h3>
        <p>Static analysis pulls endpoints, parameters, headers, and cookies out of source. Shadow APIs, deprecated routes, and undocumented handlers come out of the same pass, not a separate mode.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">02</div>
        <h3>Multi-Language</h3>
        <p>Crystal, Ruby, Python, Go, Java, Kotlin, JS/TS, PHP, C#, and more. 50+ frameworks in a single binary, no plugins or per-language setup.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">03</div>
        <h3>LLM Fallback</h3>
        <p>Frameworks Noir doesn't natively support fall back to an LLM (OpenAI, Ollama, etc.). Point it at the codebase and let the model fill the gap.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">04</div>
        <h3>CI/CD Friendly</h3>
        <p>GitHub Action, SARIF output, exit codes. Fits the pipeline you already have.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">05</div>
        <h3>For Humans, AI, and DAST</h3>
        <p>The same endpoint inventory serves all three: human reviewers and LLM-based code auditors get a focused list of attacker-reachable entrypoints; DAST scanners (ZAP, Burp, Caido) get routes they wouldn't have crawled.</p>
      </div>
      <div class="feature-cell feature-full">
        <div class="feature-number">06</div>
        <h3>Flexible Output</h3>
        <div class="feature-formats">
          <code>JSON</code><code>JSONL</code><code>YAML</code><code>TOML</code><code>OpenAPI 2.0</code><code>OpenAPI 3.0</code><code>SARIF</code><code>HTML</code><code>Markdown</code><code>cURL</code><code>HTTPie</code><code>PowerShell</code><code>ADB</code><code>simctl</code><code>Postman</code><code>Mermaid</code><code>Only-URL</code><code>Only-Param</code><code>Only-Header</code><code>Only-Cookie</code><code>Only-Tag</code>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="how-section">
  <div class="how-inner">
    <p class="how-label">Workflow</p>
    <h2 class="how-title">How it runs</h2>
    <div class="how-steps">
      <div class="how-step">
        <div class="how-step-num">01</div>
        <div class="how-step-content">
          <h3>Point it at a codebase</h3>
          <p>Noir detects language, framework, and routing patterns on its own. No config to write.</p>
          <div class="how-step-code">$ noir scan ./your-project</div>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">02</div>
        <div class="how-step-content">
          <h3>Extract endpoints</h3>
          <p>Static analyzers pull out routes, parameters, and headers. An LLM fallback handles frameworks the static rules don't cover.</p>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">03</div>
        <div class="how-step-content">
          <h3>Hand off to humans, AI, or DAST</h3>
          <p>Export JSON, OpenAPI, or SARIF for human reviewers; pipe straight into ZAP, Burp, or Caido as a proxy target; or hand the inventory to an LLM-based code auditor as focused entrypoint context.</p>
          <div class="how-step-code">$ noir scan . -f oas3 --probe-via http://localhost:8090</div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="trust-section">
  <div class="trust-inner">
    <h2 class="section-title">Built With</h2>
    <div class="trust-logos">
      <img src="./images/owasp.webp" alt="OWASP" class="trust-logo">
      <img src="./images/crystal.webp" alt="Crystal" class="trust-logo">
      <img src="./images/hwaro-wide.webp" alt="Hwaro" class="trust-logo">
    </div>
  </div>
</section>

<section class="cta-section">
  <div class="cta-inner">
    <div class="cta-panel">
      <div class="cta-panel-mascot">
        <img src="images/hak-2.webp" alt="OWASP Noir Mascot - Hak" width="320" height="320">
      </div>
      <div class="cta-panel-body">
        <p class="cta-label">Open Source</p>
        <h2 class="cta-title">Join the Community</h2>
        <p class="cta-desc">OWASP Noir is built by the community. Contribute, report issues, or just star the repo.</p>
        <div class="cta-buttons">
          <a href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" class="cta-btn" target="_blank" rel="noopener noreferrer">Contributing Guide</a>
          <a href="https://github.com/owasp-noir/noir" class="cta-btn cta-btn-ghost" target="_blank" rel="noopener noreferrer">Star on GitHub</a>
        </div>
      </div>
    </div>
    <div class="cta-contributors">
      <p class="contributors-label">Thanks to our contributors</p>
      <div class="cta-image">
        <img src="https://github.com/owasp-noir/noir/raw/main/docs/static/CONTRIBUTORS.svg" alt="Contributors" loading="lazy">
      </div>
    </div>
  </div>
</section>
