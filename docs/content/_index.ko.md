+++
title = "OWASP Noir"
template = "landing"
+++

<section class="hero">
  <div class="hero-grid-bg"></div>
  <div class="hero-inner">
    <div class="hero-eyebrow">
      <span class="hero-badge">v0.28.0</span>
      <span class="hero-badge hero-badge-owasp">OWASP Project</span>
    </div>
    <h1 class="hero-title">
      <span class="hero-title-line">Endpoint를 사냥하고,</span>
      <span class="hero-title-line">Shadow API를 드러내고,</span>
      <span class="hero-title-line hero-title-accent">공격 표면을 매핑합니다.</span>
    </h1>
    <div class="hero-terminal">
      <div class="hero-terminal-bar">
        <span class="terminal-dot"></span><span class="terminal-dot"></span><span class="terminal-dot"></span>
        <span class="terminal-title">noir</span>
      </div>
      <div class="hero-terminal-body">
        <div class="terminal-line"><span class="t-prompt">$</span> noir -b .</div>
        <div class="terminal-line t-dim">  <span class="t-info">INFO</span> Detected 1 technologies: crystal_kemal</div>
        <div class="terminal-line t-dim">  <span class="t-info">INFO</span> Analysis Started. Code Analyzer: 1 in use</div>
        <div class="terminal-line"><span class="t-success">Finally identified 6 endpoints.</span> <span class="t-dim">in 0.0032s</span></div>
        <div class="terminal-line"></div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /</div>
        <div class="terminal-line"><span class="t-method t-post">POST</span> /query</div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /token</div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /socket <span class="t-tag">websocket</span></div>
        <div class="terminal-line"><span class="t-method t-post">POST</span> /admin/config <span class="t-tag">shadow</span></div>
        <div class="terminal-line"><span class="t-method t-get">GET</span> /admin/debug <span class="t-tag">shadow</span></div>
        <div class="terminal-line terminal-cursor"></div>
      </div>
    </div>
    <div class="hero-actions">
      <a href="./get_started/overview" class="hero-btn hero-btn-primary">
        <span>시작하기</span>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
      </a>
      <a href="https://github.com/owasp-noir/noir" class="hero-btn hero-btn-secondary">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
        <span>GitHub</span>
      </a>
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
      <span class="stat-value">8</span>
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
    <p class="features-label">기능</p>
    <h2 class="features-title">소스 코드에서 공격 표면까지, 몇 초 만에</h2>
    <div class="features-grid">
      <div class="feature-cell feature-wide">
        <div class="feature-number">01</div>
        <h3>공격 표면 발견</h3>
        <p>소스 코드를 분석하여 숨겨진 엔드포인트, Shadow API, 문서화되지 않은 경로, 수동 검토에서 놓치는 보안 사각지대를 포함한 전체 공격 표면을 발견합니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">02</div>
        <h3>다중 언어</h3>
        <p>Crystal, Ruby, Python, Go, Java, Kotlin, JS/TS, PHP, C# 등. 하나의 도구로 전체 스택을 커버합니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">03</div>
        <h3>AI 기반</h3>
        <p>LLM 통합으로 미지원 프레임워크에서도 엔드포인트를 탐지합니다. 빠져나가는 것은 없습니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">04</div>
        <h3>DevSecOps 지원</h3>
        <p>CI/CD 네이티브. GitHub Actions, JSON/YAML/SARIF 출력. ZAP, Burp, Caido에 바로 연결.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">05</div>
        <h3>SAST-DAST 브릿지</h3>
        <p>발견된 엔드포인트가 동적 테스트 도구로 직접 전달됩니다. 정적 분석과 동적 스캐닝을 결합하여 완전한 커버리지를 제공합니다.</p>
      </div>
      <div class="feature-cell feature-full">
        <div class="feature-number">06</div>
        <h3>유연한 출력</h3>
        <div class="feature-formats">
          <code>JSON</code><code>YAML</code><code>OpenAPI</code><code>SARIF</code><code>cURL</code><code>HTML</code><code>Mermaid</code><code>OAS</code>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="how-section">
  <div class="how-inner">
    <p class="how-label">워크플로</p>
    <h2 class="how-title">세 단계로 완전한 가시성 확보</h2>
    <div class="how-steps">
      <div class="how-step">
        <div class="how-step-num">01</div>
        <div class="how-step-content">
          <h3>코드베이스를 지정하세요</h3>
          <p>Noir가 언어, 프레임워크, 라우팅 패턴을 자동 감지합니다. 별도의 설정이 필요하지 않습니다.</p>
          <div class="how-step-code">$ noir -b ./your-project</div>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">02</div>
        <div class="how-step-content">
          <h3>모든 엔드포인트를 발견하세요</h3>
          <p>정적 분석으로 모든 라우트, 파라미터, 헤더를 매핑합니다. AI가 알려지지 않은 프레임워크의 빈틈을 채웁니다.</p>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">03</div>
        <div class="how-step-content">
          <h3>파이프라인에 연결하세요</h3>
          <p>JSON, OpenAPI, SARIF로 내보내거나 DAST 도구에 직접 전송합니다. 한 줄로 CI/CD에 통합됩니다.</p>
          <div class="how-step-code">$ noir -b . -f oas3 --send-proxy http://localhost:8090</div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="trust-section">
  <div class="trust-inner">
    <h2 class="section-title">Built With</h2>
    <div class="trust-logos">
      <img src="../images/owasp.png" alt="OWASP" class="trust-logo">
      <img src="../images/crystal.png" alt="Crystal" class="trust-logo">
    </div>
  </div>
</section>

<section class="cta-section">
  <div class="cta-inner">
    <p class="cta-label">Open Source</p>
    <h2 class="cta-title">커뮤니티에 참여하세요</h2>
    <p class="section-desc">OWASP Noir는 커뮤니티가 만듭니다. 기여하고, 이슈를 보고하고, 스타를 눌러주세요.</p>
    <div class="cta-buttons">
      <a href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" class="cta-btn" target="_blank" rel="noopener noreferrer">기여 가이드</a>
      <a href="https://github.com/owasp-noir/noir" class="cta-btn cta-btn-ghost" target="_blank" rel="noopener noreferrer">GitHub에서 스타</a>
    </div>
    <div class="cta-image">
      <img src="https://github.com/owasp-noir/noir/raw/main/docs/static/CONTRIBUTORS.svg" alt="Contributors" loading="lazy">
    </div>
  </div>
</section>
