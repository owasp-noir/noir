+++
title = "OWASP Noir"
description = "코드 속 모든 엔드포인트를 찾아냅니다. Noir는 23개 언어와 144개 프레임워크의 소스를 정적 분석하여 섀도우 API를 드러내고 공격 표면을 그립니다."
template = "landing"
+++

<!-- CommonMark 는 빈 줄에서 HTML 블록을 끝냅니다. 그다음 줄이 4칸 이상 들여쓰여
     있으면 코드 블록이 되어 버립니다. 그래서 <section> 안에는 빈 줄을 두지 않고,
     섹션 사이만 빈 줄로 구분하며 각 섹션은 0열에서 시작합니다.

     이 페이지는 /ko/ 에 있으므로 이미지 경로는 ../ 로 한 단계 올라가야 하고,
     문서 링크는 ./ 로 두어야 /ko/ 아래에 머무릅니다. -->

<section class="hero">
  <div class="hero-sentinel" aria-hidden="true"></div>
  <div class="hero-media">
    <picture class="hero-plate hero-plate-dark">
      <source srcset="../images/noir-wallpaper.webp" type="image/webp">
      <img class="hero-art" src="../images/noir-wallpaper.jpg"
           alt="흑백으로 촬영한 인적 없는 밤거리 위에 OWASP Noir 워드마크가 빛으로 새겨져 있다."
           width="1168" height="784" fetchpriority="high" decoding="async">
    </picture>
    <picture class="hero-plate hero-plate-light">
      <source srcset="../images/noir-wallpaper-white.webp" type="image/webp">
      <img class="hero-art" src="../images/noir-wallpaper-white.jpg"
           alt="안개 낀 대낮의 인적 없는 거리 위로 OWASP Noir 워드마크가 그림자로 드리워져 있다."
           width="1248" height="832" fetchpriority="high" decoding="async">
    </picture>
    <div class="hero-scrim" aria-hidden="true"></div>
  </div>
  <div class="hero-inner">
    <div class="hero-copy">
      <h1>코드 속 모든 엔드포인트를 찾아냅니다.</h1>
      <p class="hero-sub">Noir는 소스를 읽어 공격자가 도달할 수 있는 경로와 파라미터, 헤더를 돌려줍니다.</p>
      <div class="hero-actions">
        <a class="btn btn-primary" href="./get_started/overview/">
          시작하기
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
  <h2 class="sr-only">함께 만든 기술</h2>
  <div class="wrap logowall-inner">
    <a href="https://owasp.org/www-project-noir/" target="_blank" rel="noopener noreferrer">
      <img src="../images/owasp.webp" alt="OWASP" width="500" height="174" loading="lazy" decoding="async">
    </a>
    <a href="https://crystal-lang.org/" target="_blank" rel="noopener noreferrer">
      <img src="../images/crystal.webp" alt="Crystal" width="500" height="174" loading="lazy" decoding="async">
    </a>
    <a href="https://hwaro.hahwul.com/" target="_blank" rel="noopener noreferrer">
      <img src="../images/hwaro-wide.webp" alt="Hwaro" width="1316" height="483" loading="lazy" decoding="async">
    </a>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">무엇을 하나요</h2>
    <p class="section-lede">소스를 한 번 훑어, 리뷰어와 모델과 스캐너가 모두 필요로 하는 엔드포인트 목록을 만듭니다.</p>
  </header>
  <div class="bento">
    <article class="cell cell-a" data-reveal>
      <div class="cell-body">
        <h3>엔드포인트 추출</h3>
        <p>정적 분석으로 코드에서 경로와 메서드, 파라미터, 헤더, 쿠키를 뽑아냅니다. 섀도우 API와 잊혀진 핸들러도 별도 모드가 아니라 같은 패스에서 함께 드러납니다.</p>
      </div>
      <div class="cell-shot">
        <img src="../images/landing/bento-endpoints.webp" alt="코드베이스에서 추출한 HTTP 메서드와 경로, 헤더, idor 태그가 소스 트리와 나란히 표시된 Noir 출력." width="1420" height="564" loading="lazy" decoding="async">
      </div>
    </article>
    <article class="cell cell-b" data-reveal style="--reveal-delay: 70ms">
      <div class="cell-body">
        <h3>AI 리뷰어를 위한 컨텍스트</h3>
        <p><code>--ai-context</code>는 각 엔드포인트에 가드와 싱크, 검증기, 시그널을 붙입니다. 모델이 저장소 전체 대신 핸들러를 읽게 됩니다.</p>
      </div>
      <div class="cell-shot">
        <img src="../images/landing/bento-aicontext.webp" alt="엔드포인트별 AI 컨텍스트: 라우트 정의와 탐지된 프레임워크, 리뷰어가 확인해야 할 시그널." width="790" height="530" loading="lazy" decoding="async">
      </div>
    </article>
    <article class="cell cell-c" data-reveal>
      <div class="cell-body">
        <h3>주요 스택 전부</h3>
        <p>플러그인도, 언어별 설정도 없는 단일 바이너리입니다. 정적 규칙이 놓친 프레임워크는 LLM이 대신 처리합니다.</p>
        <div class="stat-row">
          <span><span class="stat-val">23</span><span class="stat-key">언어</span></span>
          <span><span class="stat-val">144</span><span class="stat-key">프레임워크</span></span>
        </div>
      </div>
    </article>
    <article class="cell cell-d cell-plate" data-reveal style="--reveal-delay: 70ms">
      <div class="cell-body">
        <h3>패시브 스캐닝</h3>
        <p>심각도가 매겨진 규칙이 같은 트리를 훑어 하드코딩된 키와 토큰, 자격 증명을 보고합니다. 직접 만든 규칙이나 커뮤니티 규칙을 쓸 수 있습니다.</p>
      </div>
    </article>
    <article class="cell cell-e" data-reveal style="--reveal-delay: 140ms">
      <div class="cell-body">
        <h3>의미 태그</h3>
        <p>17개의 태거가 어디부터 살펴봐야 하는지 알려주는 속성을 엔드포인트에 붙입니다.</p>
        <div class="tag-cloud">
          <code>cors</code><code>jwt</code><code>oauth</code><code>graphql</code><code>pii</code><code>payment</code><code>file_upload</code><code>webhook</code><code>websocket</code><code>soap</code><code>crypto</code><code>debug</code><code>admin</code><code>account_recovery</code><code>api_docs</code><code>hunt_param</code><code>mcp</code>
        </div>
      </div>
    </article>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">어떻게 동작하나요</h2>
  </header>
  <div class="flow">
    <div class="flow-step" data-reveal>
      <h3>코드베이스를 가리키세요</h3>
      <p>Noir가 언어와 프레임워크, 라우팅 방식을 스스로 알아냅니다. 미리 설정할 것은 없습니다.</p>
      <code class="flow-cmd">noir scan ./your-project</code>
    </div>
    <div class="flow-step" data-reveal>
      <h3>찾아낸 결과를 읽으세요</h3>
      <p>모든 엔드포인트는 출처가 된 파일과 줄 번호를 함께 갖고 있어, 결과에서 코드까지 한 번에 이동합니다.</p>
      <code class="flow-cmd">noir scan ./your-project --include path,techs -f json -o endpoints.json</code>
    </div>
    <div class="flow-step" data-reveal>
      <h3>다음 도구로 넘기세요</h3>
      <p>스캐너에는 OpenAPI를, 코드 스캐닝 대시보드에는 SARIF를 내보내거나, 인터셉트 프록시로 요청을 바로 흘려보내세요.</p>
      <code class="flow-cmd">noir scan ./your-project -f oas3 --probe-via http://127.0.0.1:8080</code>
    </div>
  </div>
</section>

<section class="section wrap">
  <header class="section-head" data-reveal>
    <h2 class="section-title">출력 형식</h2>
    <p class="section-lede">스물두 가지. 다음 도구가 이미 알아듣는 형식을 고르세요.</p>
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
      <h2 class="section-title">하나의 목록, 세 부류의 독자</h2>
      <div class="split-list">
        <div class="split-item">
          <h3>보안 리뷰어</h3>
          <p>저장소를 통째로 훑는 대신, 공격자가 도달할 수 있는 진입점만 추린 목록을 받습니다.</p>
        </div>
        <div class="split-item">
          <h3>AI 코드 감사자</h3>
          <p>같은 목록에 더해 각 엔드포인트를 둘러싼 가드와 싱크, 검증기까지 함께 받습니다.</p>
        </div>
        <div class="split-item">
          <h3>DAST 스캐너</h3>
          <p>크롤러가 결코 닿지 못할 경로를 프록시 대상이나 OpenAPI 문서로 ZAP과 Burp, Caido에 넘깁니다.</p>
        </div>
      </div>
    </div>
    <div class="split-shot" data-reveal style="--reveal-delay: 90ms">
      <img src="../images/report-dark.webp" alt="발견한 엔드포인트와 메서드, 파라미터, 태그를 나열한 Noir HTML 리포트." width="1280" height="1080" loading="lazy" decoding="async">
    </div>
  </div>
</section>

<section class="section wrap">
  <div class="community-inner">
    <div class="poster-frame" data-reveal>
      <img src="../images/hak-poster.webp" alt="빗속에 트렌치코트와 고글 차림으로 서 있는 OWASP Noir 마스코트 학의 영화 포스터." width="2000" height="1116" loading="lazy" decoding="async">
    </div>
    <div class="community-copy" data-reveal style="--reveal-delay: 90ms">
      <h2 class="section-title">공개적으로 만듭니다</h2>
      <p>Noir는 OWASP 재단 프로젝트이며 MIT 라이선스로 배포되고, 실제로 사용하는 사람들이 관리합니다. 프레임워크 지원과 스캔 규칙, 출력 형식은 모두 기여로 채워집니다.</p>
      <a class="btn btn-outline" href="https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" target="_blank" rel="noopener noreferrer">
        기여 가이드 읽기
        <svg class="ic" aria-hidden="true"><use href="#i-arrow-up-right"/></svg>
      </a>
    </div>
  </div>
  <div class="contributors" data-reveal>
    <p>기여해 주신 모든 분께 감사드립니다.</p>
    <img src="../CONTRIBUTORS.svg" alt="OWASP Noir에 기여한 사람들의 프로필 이미지." width="740" height="222" loading="lazy" decoding="async">
  </div>
</section>
