+++
template = "landing"
+++

<section class="hero">
  <div class="hero-grid-bg"></div>
  <div class="hero-scanline"></div>
  <div class="hero-noise"></div>
  <div class="hero-inner">
    <div class="hero-eyebrow">
      <span class="hero-badge">v0.28.0</span>
      <span class="hero-badge hero-badge-owasp">OWASP Project</span>
    </div>
    <h1 class="hero-title">
      <span class="hero-title-line">Hunt Endpoints.</span>
      <span class="hero-title-line">Expose <span class="hero-glitch" data-text="Shadow APIs">Shadow APIs</span>.</span>
      <span class="hero-title-line hero-title-accent">Map the Attack Surface.</span>
    </h1>
    <div class="hero-terminal">
      <div class="hero-terminal-bar">
        <span class="terminal-dot"></span><span class="terminal-dot"></span><span class="terminal-dot"></span>
        <span class="terminal-title">noir</span>
      </div>
      <div class="hero-terminal-body">
        <div class="terminal-line"><span class="t-prompt">$</span> noir -b . -u https://testapp.com</div>
        <div class="terminal-line t-dim">  <span class="t-info">INFO</span> Discovering endpoints...</div>
        <div class="terminal-line t-dim">  <span class="t-info">INFO</span> Found mass_assignment vulnerability in users_controller</div>
        <div class="terminal-line"><span class="t-success">Found 47 endpoints</span> <span class="t-dim">in 1.2s</span></div>
        <div class="terminal-line"></div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /api/users</div>
        <div class="terminal-line"><span class="t-method t-post">POST</span> /api/users/login</div>
        <div class="terminal-line"><span class="t-method t-put">PUT</span> /api/users/:id</div>
        <div class="terminal-line"><span class="t-method t-del">DELETE</span> /api/users/:id</div>
        <div class="terminal-line"><span class="t-method t-post">POST</span> /api/admin/config <span class="t-tag">shadow</span></div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /api/internal/debug <span class="t-tag">shadow</span></div>
        <div class="terminal-line t-dim">  ... and 41 more</div>
        <div class="terminal-line terminal-cursor"></div>
      </div>
    </div>
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
</section>

<div class="marquee-bar">
  <div class="marquee-track">
    <span class="marquee-item"><strong>50+</strong> Languages & Frameworks</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>8</strong> Output Formats</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>AI</strong> Powered Analysis</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>OWASP</strong> Official Project</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>SAST</strong> to <strong>DAST</strong> Bridge</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>Open</strong> Source</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>50+</strong> Languages & Frameworks</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>8</strong> Output Formats</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>AI</strong> Powered Analysis</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>OWASP</strong> Official Project</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>SAST</strong> to <strong>DAST</strong> Bridge</span>
    <span class="marquee-sep">/</span>
    <span class="marquee-item"><strong>Open</strong> Source</span>
    <span class="marquee-sep">/</span>
  </div>
</div>

<section class="bento-section">
  <div class="bento-inner">
    <h2 class="bento-heading">What Noir does</h2>
    <div class="bento-grid">
      <div class="bento-card bento-wide">
        <div class="bento-number">01</div>
        <h3>Attack Surface Discovery</h3>
        <p>Analyzes source code to uncover the complete attack surface &mdash; hidden endpoints, shadow APIs, undocumented routes, and security blind spots that manual review misses.</p>
      </div>
      <div class="bento-card">
        <div class="bento-number">02</div>
        <h3>Multi-Language</h3>
        <p>Crystal, Ruby, Python, Go, Java, Kotlin, JS/TS, PHP, C#, and more. One tool for your entire stack.</p>
      </div>
      <div class="bento-card">
        <div class="bento-number">03</div>
        <h3>AI-Powered</h3>
        <p>LLM integration detects endpoints even in unsupported frameworks. Nothing escapes.</p>
      </div>
      <div class="bento-card">
        <div class="bento-number">04</div>
        <h3>DevSecOps Ready</h3>
        <p>CI/CD native. GitHub Actions, JSON/YAML/SARIF output. Plug into ZAP, Burp, Caido.</p>
      </div>
      <div class="bento-card bento-wide">
        <div class="bento-number">05</div>
        <h3>SAST-to-DAST Bridge</h3>
        <p>Discovered endpoints feed directly into dynamic testing tools. Static analysis meets dynamic scanning for full coverage.</p>
      </div>
      <div class="bento-card bento-full">
        <div class="bento-number">06</div>
        <h3>Flexible Output</h3>
        <div class="bento-formats">
          <code>JSON</code><code>YAML</code><code>OpenAPI</code><code>SARIF</code><code>cURL</code><code>HTML</code><code>Mermaid</code><code>OAS</code>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="trust-section">
  <div class="trust-inner">
    <h2 class="section-title">Built With</h2>
    <div class="trust-logos">
      <img src="./images/owasp.png" alt="OWASP" class="trust-logo">
      <img src="./images/crystal.png" alt="Crystal" class="trust-logo">
    </div>
  </div>
</section>

<section class="cta-section">
  <div class="cta-glow"></div>
  <div class="cta-inner">
    <p class="cta-label">Open Source</p>
    <h2 class="cta-title">Join the Community</h2>
    <p class="section-desc">OWASP Noir is built by the community. Contribute, report issues, or just star the repo.</p>
    <div class="cta-buttons">
      <a href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" class="cta-btn" target="_blank" rel="noopener noreferrer">Contributing Guide</a>
      <a href="https://github.com/owasp-noir/noir" class="cta-btn cta-btn-ghost" target="_blank" rel="noopener noreferrer">Star on GitHub</a>
    </div>
    <div class="cta-image">
      <img src="https://github.com/owasp-noir/noir/raw/main/docs/static/CONTRIBUTORS.svg" alt="Contributors" loading="lazy">
    </div>
  </div>
</section>
