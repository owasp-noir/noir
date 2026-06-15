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
        <span class="hero-title-line">Endpoint를 사냥하고,</span>
        <span class="hero-title-line">Shadow API를 드러내고,</span>
        <span class="hero-title-line hero-title-accent">공격 표면을 매핑합니다.</span>
      </h1>
      <p class="hero-desc">50개 이상의 프레임워크 소스 코드를 분석해 엔드포인트, 파라미터, 숨겨진 라우트를 찾아냅니다. 결과는 리뷰어, AI 감사자, 실제 라우트가 필요한 DAST 스캐너에 그대로 전달됩니다.</p>
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
    <div class="hero-showcase">
      <div class="split-stage">
        <div class="split-pane split-a">
          <img src="../images/landing/1.webp" alt="소스 코드를 사람이 읽기 좋은 엔드포인트 목록으로 변환" width="1904" height="1162" loading="eager" decoding="async" fetchpriority="high">
          <span class="split-tag">source &rarr; endpoints</span>
        </div>
        <div class="split-pane split-b">
          <img src="../images/landing/2.webp" alt="엔드포인트별 AI 컨텍스트: callee, guard, 보안 시그널" width="1904" height="1162" loading="lazy" decoding="async">
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
    <p class="features-label">기능</p>
    <h2 class="features-title">하는 일</h2>
    <div class="features-grid">
      <div class="feature-cell feature-wide">
        <div class="feature-number">01</div>
        <h3>엔드포인트 추출</h3>
        <p>정적 분석으로 소스에서 엔드포인트, 파라미터, 헤더, 쿠키를 끌어냅니다. Shadow API, 사장된 라우트, 문서화되지 않은 핸들러도 같은 패스에서 함께 나옵니다. 별도의 모드가 아닙니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">02</div>
        <h3>다중 언어</h3>
        <p>Crystal, Ruby, Python, Go, Java, Kotlin, JS/TS, PHP, C# 등 50개 이상의 프레임워크를 단일 바이너리로 지원합니다. 플러그인이나 언어별 설정은 필요 없습니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">03</div>
        <h3>LLM 폴백</h3>
        <p>네이티브로 지원하지 않는 프레임워크는 LLM(OpenAI, Ollama 등)에 위임합니다. 코드베이스를 가리키면 모델이 빈 자리를 채웁니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">04</div>
        <h3>CI/CD 친화</h3>
        <p>GitHub Action, SARIF 출력, exit code. 이미 쓰고 있는 파이프라인에 그대로 끼워 넣습니다.</p>
      </div>
      <div class="feature-cell">
        <div class="feature-number">05</div>
        <h3>사람, AI, DAST 모두를 위한</h3>
        <p>같은 엔드포인트 인벤토리가 셋 모두에게 필요한 입력입니다. 사람 리뷰어와 LLM 기반 코드 감사자는 저장소 전체 대신 공격자 도달 가능한 진입점 목록에 집중할 수 있고, DAST 스캐너(ZAP, Burp, Caido)는 크롤링으로는 닿지 못했을 라우트까지 받아 갑니다.</p>
      </div>
      <div class="feature-cell feature-full">
        <div class="feature-number">06</div>
        <h3>유연한 출력</h3>
        <div class="feature-formats">
          <code>JSON</code><code>JSONL</code><code>YAML</code><code>TOML</code><code>OAS2</code><code>OAS3</code><code>SARIF</code><code>HTML</code><code>Markdown</code><code>cURL</code><code>HTTPie</code><code>PowerShell</code><code>ADB</code><code>simctl</code><code>Postman</code><code>Mermaid</code><code>Only-URL</code><code>Only-Param</code><code>Only-Header</code><code>Only-Cookie</code><code>Only-Tag</code>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="how-section">
  <div class="how-inner">
    <p class="how-label">워크플로</p>
    <h2 class="how-title">실행 방식</h2>
    <div class="how-steps">
      <div class="how-step">
        <div class="how-step-num">01</div>
        <div class="how-step-content">
          <h3>코드베이스를 지정</h3>
          <p>Noir가 언어, 프레임워크, 라우팅 패턴을 알아서 감지합니다. 작성할 설정은 없습니다.</p>
          <div class="how-step-code">$ noir scan ./your-project</div>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">02</div>
        <div class="how-step-content">
          <h3>엔드포인트 추출</h3>
          <p>정적 분석기가 라우트, 파라미터, 헤더를 끌어냅니다. 정적 규칙으로 커버하지 못하는 프레임워크는 LLM 폴백이 처리합니다.</p>
        </div>
      </div>
      <div class="how-step">
        <div class="how-step-num">03</div>
        <div class="how-step-content">
          <h3>사람, AI, DAST에 전달</h3>
          <p>사람 리뷰어를 위해 JSON, OpenAPI, SARIF로 내보내거나, ZAP·Burp·Caido에 프록시 타깃으로 그대로 흘려보내거나, LLM 기반 코드 감사자에게 집중된 진입점 컨텍스트로 넘기면 됩니다.</p>
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
        <img src="../images/owasp.webp" alt="OWASP" class="trust-logo">
        <img src="../images/crystal.webp" alt="Crystal" class="trust-logo">
        <img src="../images/hwaro-wide.webp" alt="Hwaro" class="trust-logo">
    </div>
  </div>
</section>

<section class="cta-section">
  <div class="cta-inner">
    <div class="cta-panel">
      <div class="cta-panel-mascot">
        <img src="../images/hak-2.webp" alt="OWASP Noir Mascot - Hak" width="320" height="320">
      </div>
      <div class="cta-panel-body">
        <p class="cta-label">Open Source</p>
        <h2 class="cta-title">커뮤니티에 참여하세요</h2>
        <p class="cta-desc">OWASP Noir는 커뮤니티가 만듭니다. 기여하고, 이슈를 보고하고, 스타를 눌러주세요.</p>
        <div class="cta-buttons">
          <a href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" class="cta-btn" target="_blank" rel="noopener noreferrer">기여 가이드</a>
          <a href="https://github.com/owasp-noir/noir" class="cta-btn cta-btn-ghost" target="_blank" rel="noopener noreferrer">GitHub에서 스타</a>
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
