# Stylesheet for the self-contained HTML report.
# Everything ships inline; no external fonts, images, or scripts.
module HtmlReportAssets
  STYLES = <<-CSS
    /* ===== OWASP Noir report theme ==================================
       Dark-tech base with restrained semantic color: hue is reserved
       for meaning (HTTP method risk, finding severity, one emerald
       brand accent). Chrome stays neutral in both themes. */
    :root {
      --bg: #fafafa;
      --bg-subtle: #f3f3f4;
      --surface: #fdfdfd;
      --ink: #111114;
      --ink-2: #404046;
      --ink-3: #6f6f7a;
      --line: #e6e6e9;
      --line-2: #d2d2d8;
      --fill: #141418;
      --on-fill: #f7f7f8;
      --hover: #f0f0f2;
      --selection: rgba(17, 17, 20, 0.12);
      --accent: #ee2a22;
      --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      --font-mono: ui-monospace, "SF Mono", SFMono-Regular, "JetBrains Mono", Menlo, Consolas, "Liberation Mono", monospace;
      /* semantic method hues (AA on --bg / tint backgrounds) */
      --m-get: #047857;
      --m-get-soft: rgba(4, 120, 87, 0.08);
      --m-get-line: rgba(4, 120, 87, 0.38);
      --m-post: #854d0e;
      --m-post-soft: rgba(180, 83, 9, 0.10);
      --m-post-line: rgba(180, 83, 9, 0.42);
      --m-put: #1d4ed8;
      --m-put-soft: rgba(29, 78, 216, 0.08);
      --m-put-line: rgba(29, 78, 216, 0.38);
      --m-patch: #6d28d9;
      --m-patch-soft: rgba(109, 40, 217, 0.08);
      --m-patch-line: rgba(109, 40, 217, 0.38);
      --m-delete: #be123c;
      --m-delete-soft: rgba(190, 18, 60, 0.08);
      --m-delete-line: rgba(190, 18, 60, 0.38);
      /* semantic severity hues */
      --sev-critical-bg: #b91c1c;
      --sev-critical-ink: #fdf2f2;
      --sev-high: #b91c1c;
      --sev-high-soft: rgba(185, 28, 28, 0.08);
      --sev-high-line: rgba(185, 28, 28, 0.40);
      --sev-medium: #854d0e;
      --sev-medium-soft: rgba(180, 83, 9, 0.10);
      --sev-medium-line: rgba(180, 83, 9, 0.42);
      --sev-low: #475569;
      --sev-low-soft: rgba(71, 85, 105, 0.08);
      --sev-low-line: rgba(71, 85, 105, 0.38);
    }
    [data-theme="dark"] {
      --bg: #050507;
      --bg-subtle: #0a0a0e;
      --surface: #0b0b10;
      --ink: #ededf0;
      --ink-2: #b4b4c2;
      --ink-3: #74748a;
      --line: #1a1a22;
      --line-2: #2a2a36;
      --fill: #ededf0;
      --on-fill: #0b0b10;
      --hover: #131319;
      --selection: rgba(237, 237, 240, 0.16);
      --accent: #ff6a5e;
      --m-get: #34d399;
      --m-get-soft: rgba(52, 211, 153, 0.09);
      --m-get-line: rgba(52, 211, 153, 0.34);
      --m-post: #fbbf24;
      --m-post-soft: rgba(251, 191, 36, 0.09);
      --m-post-line: rgba(251, 191, 36, 0.34);
      --m-put: #60a5fa;
      --m-put-soft: rgba(96, 165, 250, 0.09);
      --m-put-line: rgba(96, 165, 250, 0.34);
      --m-patch: #a78bfa;
      --m-patch-soft: rgba(167, 139, 250, 0.09);
      --m-patch-line: rgba(167, 139, 250, 0.34);
      --m-delete: #f87171;
      --m-delete-soft: rgba(248, 113, 113, 0.09);
      --m-delete-line: rgba(248, 113, 113, 0.34);
      --sev-critical-bg: #e05252;
      --sev-critical-ink: #0b0b10;
      --sev-high: #f87171;
      --sev-high-soft: rgba(248, 113, 113, 0.09);
      --sev-high-line: rgba(248, 113, 113, 0.36);
      --sev-medium: #fbbf24;
      --sev-medium-soft: rgba(251, 191, 36, 0.09);
      --sev-medium-line: rgba(251, 191, 36, 0.34);
      --sev-low: #94a3b8;
      --sev-low-soft: rgba(148, 163, 184, 0.09);
      --sev-low-line: rgba(148, 163, 184, 0.34);
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    ::selection { background: var(--selection); }
    html { scroll-behavior: smooth; }
    body {
      font-family: var(--font-sans);
      background: var(--bg);
      color: var(--ink);
      line-height: 1.6;
      font-size: 15px;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      transition: background-color 0.2s ease, color 0.2s ease;
    }
    .container { max-width: 1200px; margin: 0 auto; padding: 0 1.5rem; }
    a { color: inherit; }
    .visually-hidden {
      position: absolute;
      width: 1px; height: 1px;
      margin: -1px; padding: 0;
      overflow: hidden;
      clip: rect(0 0 0 0);
      white-space: nowrap;
      border: 0;
    }

    /* ===== Header ================================================= */
    .report-header {
      border-top: 2px solid var(--accent);
      border-bottom: 1px solid var(--line);
      background: var(--bg);
    }
    .report-header .container {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      padding-top: 1.75rem;
      padding-bottom: 1.75rem;
    }
    .brand { display: flex; align-items: center; gap: 0.85rem; min-width: 0; }
    .brand-mark {
      width: 38px; height: 38px;
      flex-shrink: 0;
      display: block;
    }
    .brand-text { display: flex; flex-direction: column; min-width: 0; }
    .brand-eyebrow {
      font-family: var(--font-mono);
      font-size: 0.66rem;
      letter-spacing: 0.28em;
      text-transform: uppercase;
      color: var(--ink-3);
    }
    .brand-title {
      font-family: var(--font-mono);
      font-size: 1.4rem;
      font-weight: 700;
      letter-spacing: -0.02em;
      line-height: 1.1;
    }
    .header-actions { display: flex; align-items: center; gap: 1.25rem; flex-shrink: 0; }
    .header-tagline {
      font-family: var(--font-mono);
      font-size: 0.72rem;
      color: var(--ink-3);
      text-align: right;
    }
    .theme-toggle {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 40px; height: 40px;
      padding: 0;
      background: var(--surface);
      color: var(--ink);
      border: 1px solid var(--line-2);
      cursor: pointer;
      transition: background-color 0.15s ease, border-color 0.15s ease, transform 0.1s ease;
    }
    .theme-toggle:hover { background: var(--hover); border-color: var(--ink-3); }
    .theme-toggle:active { transform: scale(0.95); }
    .theme-toggle:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
    .theme-toggle svg { width: 17px; height: 17px; display: block; }
    .theme-toggle .icon-sun { display: none; }
    [data-theme="dark"] .theme-toggle .icon-sun { display: block; }
    [data-theme="dark"] .theme-toggle .icon-moon { display: none; }

    /* ===== Layout ================================================= */
    main.container { padding-top: 2.5rem; padding-bottom: 2.5rem; }
    .section { margin-bottom: 3rem; }
    .section-title {
      font-family: var(--font-mono);
      font-size: 0.8rem;
      font-weight: 700;
      letter-spacing: 0.18em;
      text-transform: uppercase;
      color: var(--ink-2);
      display: flex;
      align-items: center;
      gap: 0.6rem;
      padding-bottom: 0.6rem;
      margin-bottom: 1.25rem;
      border-bottom: 1px solid var(--line);
    }
    .section-title::before {
      content: "";
      width: 9px; height: 9px;
      background: var(--accent);
      flex-shrink: 0;
    }
    .section-count {
      margin-left: auto;
      font-weight: 500;
      color: var(--ink-3);
      letter-spacing: 0.08em;
      font-variant-numeric: tabular-nums;
    }

    /* ===== Controls: search, filter chips, view toggle ============ */
    .controls {
      position: sticky;
      top: 0;
      z-index: 20;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      flex-wrap: wrap;
      padding: 0.7rem 0;
      margin-bottom: 1.25rem;
      background: var(--bg);
      border-bottom: 1px solid var(--line);
    }
    .search { position: relative; flex: 1 1 260px; display: flex; align-items: center; }
    .search svg {
      position: absolute; left: 0.65rem;
      width: 15px; height: 15px;
      color: var(--ink-3);
      pointer-events: none;
    }
    .search input {
      width: 100%;
      font-family: var(--font-mono);
      font-size: 0.82rem;
      color: var(--ink);
      background: var(--surface);
      border: 1px solid var(--line-2);
      padding: 0.5rem 0.6rem 0.5rem 1.95rem;
    }
    .search input::placeholder { color: var(--ink-3); }
    .search input:focus { outline: none; border-color: var(--accent); }
    .search input::-webkit-search-cancel-button { -webkit-appearance: none; }
    .chips { display: flex; gap: 0.4rem; flex-wrap: wrap; }
    .chip {
      font-family: var(--font-mono);
      font-size: 0.68rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 0.4rem 0.65rem;
      color: var(--ink-2);
      background: var(--surface);
      border: 1px solid var(--line-2);
      cursor: pointer;
      transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
    }
    .chip:hover { border-color: var(--ink-3); color: var(--ink); }
    .chip[aria-pressed="true"] { background: var(--fill); color: var(--on-fill); border-color: var(--fill); }
    .chip:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
    .chip.chip-get[aria-pressed="true"] { color: var(--m-get); background: var(--m-get-soft); border-color: var(--m-get-line); }
    .chip.chip-post[aria-pressed="true"] { color: var(--m-post); background: var(--m-post-soft); border-color: var(--m-post-line); }
    .chip.chip-put[aria-pressed="true"] { color: var(--m-put); background: var(--m-put-soft); border-color: var(--m-put-line); }
    .chip.chip-patch[aria-pressed="true"] { color: var(--m-patch); background: var(--m-patch-soft); border-color: var(--m-patch-line); }
    .chip.chip-delete[aria-pressed="true"] { color: var(--m-delete); background: var(--m-delete-soft); border-color: var(--m-delete-line); }
    .chip.chip-critical[aria-pressed="true"] { color: var(--sev-critical-ink); background: var(--sev-critical-bg); border-color: var(--sev-critical-bg); }
    .chip.chip-high[aria-pressed="true"] { color: var(--sev-high); background: var(--sev-high-soft); border-color: var(--sev-high-line); }
    .chip.chip-medium[aria-pressed="true"] { color: var(--sev-medium); background: var(--sev-medium-soft); border-color: var(--sev-medium-line); }
    .chip.chip-low[aria-pressed="true"] { color: var(--sev-low); background: var(--sev-low-soft); border-color: var(--sev-low-line); }
    .view-seg { display: inline-flex; border: 1px solid var(--line-2); }
    .view-btn {
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      font-family: var(--font-mono);
      font-size: 0.68rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 0.4rem 0.65rem;
      color: var(--ink-3);
      background: var(--surface);
      border: none;
      cursor: pointer;
      transition: background-color 0.12s ease, color 0.12s ease;
    }
    .view-btn + .view-btn { border-left: 1px solid var(--line-2); }
    .view-btn:hover { color: var(--ink); }
    .view-btn[aria-pressed="true"] { background: var(--fill); color: var(--on-fill); }
    .view-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
    .view-btn svg { width: 13px; height: 13px; display: block; }
    .no-results { display: none; }
    .no-results.show { display: block; }

    /* ===== Summary stat strip ===================================== */
    .summary {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      border: 1px solid var(--line);
      background: var(--surface);
      margin-bottom: 3rem;
    }
    .summary-card {
      padding: 1.5rem 1.5rem;
      border-left: 1px solid var(--line);
    }
    .summary-card:first-child { border-left: none; }
    .summary-card h3 {
      font-family: var(--font-mono);
      font-size: 2.4rem;
      font-weight: 700;
      line-height: 1;
      letter-spacing: -0.03em;
      font-variant-numeric: tabular-nums;
    }
    .summary-card p {
      color: var(--ink-3);
      font-family: var(--font-mono);
      font-size: 0.68rem;
      text-transform: uppercase;
      letter-spacing: 0.16em;
      margin-top: 0.55rem;
    }

    /* ===== Path groups ============================================ */
    .group { border: 1px solid var(--line); margin-bottom: -1px; }
    .group-header {
      width: 100%;
      display: flex;
      align-items: center;
      gap: 0.6rem;
      font-family: var(--font-mono);
      font-size: 0.74rem;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-align: left;
      color: var(--ink-2);
      background: var(--bg-subtle);
      border: none;
      border-bottom: 1px solid var(--line);
      padding: 0.55rem 1rem;
      cursor: pointer;
      transition: background-color 0.12s ease, color 0.12s ease;
    }
    .group-header:hover { background: var(--hover); color: var(--ink); }
    .group-header:focus-visible { outline: 2px solid var(--ink); outline-offset: -2px; }
    .group-name { word-break: break-all; }
    .group-count {
      margin-left: auto;
      font-weight: 500;
      color: var(--ink-3);
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
    }
    .group .card { border-left: none; border-right: none; }
    .group .card:last-child { border-bottom: none; margin-bottom: 0; }
    .group.collapsed .group-header { border-bottom: none; }
    .group.collapsed .group-header .chevron { transform: rotate(-90deg); }
    .group.collapsed .group-body { display: none; }
    .section.filtering .group.collapsed .group-body { display: block; }
    html[data-group="off"] .group-header { display: none; }
    html[data-group="off"] .group { border: none; margin: 0; }
    html[data-group="off"] .group .card { border: 1px solid var(--line); margin-bottom: -1px; }
    html[data-group="off"] .group.collapsed .group-body { display: block; }

    /* ===== Cards ================================================== */
    .card {
      background: var(--surface);
      border: 1px solid var(--line);
      margin-bottom: -1px;
    }
    .card:hover { border-color: var(--line-2); position: relative; z-index: 1; }
    .card-header { display: flex; align-items: stretch; }
    .card-toggle {
      flex: 1 1 auto;
      min-width: 0;
      padding: 0.85rem 1rem;
      display: flex;
      align-items: center;
      gap: 0.7rem;
      flex-wrap: wrap;
    }
    button.card-toggle {
      font: inherit;
      color: inherit;
      text-align: left;
      background: transparent;
      border: none;
      cursor: pointer;
      transition: background-color 0.12s ease;
    }
    button.card-toggle:hover { background: var(--hover); }
    button.card-toggle:focus-visible { outline: 2px solid var(--ink); outline-offset: -2px; }
    .chevron {
      width: 16px; height: 16px;
      flex-shrink: 0;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: var(--ink-3);
      transition: transform 0.2s ease;
    }
    .chevron svg { width: 12px; height: 12px; display: block; }
    .chevron-spacer { width: 16px; flex-shrink: 0; }
    .card.collapsed .chevron { transform: rotate(-90deg); }
    .card-collapse {
      display: grid;
      grid-template-rows: 1fr;
      transition: grid-template-rows 0.22s ease;
    }
    .card.collapsed .card-collapse { grid-template-rows: 0fr; }
    .card-collapse > .card-pane { overflow: hidden; min-height: 0; }
    .url {
      font-family: var(--font-mono);
      font-size: 0.88rem;
      font-weight: 500;
      word-break: break-all;
    }
    .card-details {
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
      flex-wrap: wrap;
      min-width: 0;
    }
    .card-meta {
      font-family: var(--font-mono);
      font-size: 0.66rem;
      color: var(--ink-3);
      letter-spacing: 0.05em;
      white-space: nowrap;
    }
    .card-actions {
      display: flex;
      align-items: center;
      gap: 0.15rem;
      padding: 0 0.6rem;
      border-left: 1px solid var(--line);
    }
    .copy-btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 30px; height: 30px;
      padding: 0;
      background: transparent;
      color: var(--ink-3);
      border: 1px solid transparent;
      cursor: pointer;
      transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
    }
    .copy-btn:hover { color: var(--ink); background: var(--hover); border-color: var(--line-2); }
    .copy-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 1px; }
    .copy-btn svg { width: 14px; height: 14px; display: block; }
    .copy-btn .icon-check { display: none; }
    .copy-btn.copied { color: var(--accent); }
    .copy-btn.copied .icon-copy { display: none; }
    .copy-btn.copied .icon-check { display: block; }

    /* ===== Method badges: semantic risk hues ====================== */
    .method-badge {
      display: inline-block;
      padding: 0.2rem 0.6rem;
      font-family: var(--font-mono);
      font-size: 0.7rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      border: 1px solid var(--line-2);
      min-width: 4.6em;
      text-align: center;
      flex-shrink: 0;
    }
    .method-get { color: var(--m-get); background: var(--m-get-soft); border-color: var(--m-get-line); }
    .method-post { color: var(--m-post); background: var(--m-post-soft); border-color: var(--m-post-line); }
    .method-put { color: var(--m-put); background: var(--m-put-soft); border-color: var(--m-put-line); }
    .method-patch { color: var(--m-patch); background: var(--m-patch-soft); border-color: var(--m-patch-line); }
    .method-delete { color: var(--m-delete); background: var(--m-delete-soft); border-color: var(--m-delete-line); }
    .method-default { background: transparent; color: var(--ink-3); border-color: var(--line-2); border-style: dashed; }

    .protocol-badge {
      font-family: var(--font-mono);
      font-size: 0.66rem;
      padding: 0.12rem 0.45rem;
      border: 1px solid var(--line-2);
      color: var(--ink-3);
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .tag-badge {
      display: inline-block;
      font-family: var(--font-mono);
      font-size: 0.66rem;
      padding: 0.12rem 0.45rem;
      background: var(--bg-subtle);
      border: 1px solid var(--line);
      color: var(--ink-2);
    }

    /* ===== Card body ============================================= */
    .card-body {
      padding: 0 1rem 1rem;
      border-top: 1px solid var(--line);
      padding-top: 1rem;
    }
    .params-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.84rem;
    }
    .params-table th, .params-table td {
      padding: 0.5rem 0.6rem;
      text-align: left;
      border-bottom: 1px solid var(--line);
    }
    .params-table tr:last-child td { border-bottom: none; }
    .params-table th {
      font-family: var(--font-mono);
      font-size: 0.64rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      color: var(--ink-3);
    }
    .params-table td:first-child { font-family: var(--font-mono); }
    .params-table td:last-child { font-family: var(--font-mono); color: var(--ink-2); word-break: break-all; }

    /* ===== Param-type chips: uniform monochrome ================== */
    .param-type {
      display: inline-block;
      font-family: var(--font-mono);
      padding: 0.1rem 0.4rem;
      font-size: 0.64rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      border: 1px solid var(--line-2);
      color: var(--ink-2);
    }
    .param-query, .param-json, .param-form,
    .param-header, .param-cookie, .param-path { background: var(--bg-subtle); }
    .param-path, .param-header { background: var(--ink); color: var(--on-fill); border-color: var(--ink); }

    /* ===== Severity badges: semantic ramp ======================== */
    .severity-critical { background: var(--sev-critical-bg); color: var(--sev-critical-ink); border-color: var(--sev-critical-bg); }
    .severity-high { color: var(--sev-high); background: var(--sev-high-soft); border-color: var(--sev-high-line); }
    .severity-medium { color: var(--sev-medium); background: var(--sev-medium-soft); border-color: var(--sev-medium-line); }
    .severity-low { color: var(--sev-low); background: var(--sev-low-soft); border-color: var(--sev-low-line); }
    .severity-info { background: transparent; color: var(--ink-3); border-color: var(--line-2); }
    .passive-card .card-header { padding: 0.85rem 1rem; align-items: center; gap: 0.7rem; flex-wrap: wrap; }

    .code-path {
      font-family: var(--font-mono);
      font-size: 0.76rem;
      color: var(--ink-3);
      margin-top: 0.35rem;
    }
    .code-path .marker { color: var(--ink-2); }
    .card-body p { font-size: 0.86rem; }
    .card-body p + p { margin-top: 0.5rem; }
    .card-body code {
      font-family: var(--font-mono);
      font-size: 0.8rem;
      background: var(--bg-subtle);
      border: 1px solid var(--line);
      padding: 0.05rem 0.3rem;
    }

    .empty-state {
      text-align: center;
      padding: 3rem 1rem;
      color: var(--ink-3);
      font-family: var(--font-mono);
      font-size: 0.85rem;
      border: 1px dashed var(--line-2);
    }

    /* ===== Compact table view ==================================== */
    .table-head { display: none; }
    @media (min-width: 721px) {
      html[data-view="table"] .table-head {
        display: grid;
        grid-template-columns: 16px 6.8em minmax(0, 1fr) auto;
        column-gap: 0.7rem;
        align-items: center;
        padding: 0.45rem 1rem;
        padding-right: 102px;
        font-family: var(--font-mono);
        font-size: 0.62rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        color: var(--ink-3);
        background: var(--bg-subtle);
        border: 1px solid var(--line);
        border-bottom: none;
      }
      html[data-view="table"] .table-head .th-details { justify-self: end; }
      html[data-view="table"] .card[data-endpoint] .card-toggle {
        display: grid;
        grid-template-columns: 16px 6.8em minmax(0, 1fr) auto;
        column-gap: 0.7rem;
        align-items: center;
        padding: 0.5rem 1rem;
      }
      html[data-view="table"] .card[data-endpoint] .url {
        font-size: 0.8rem;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        word-break: normal;
      }
      html[data-view="table"] .card[data-endpoint] .card-details {
        justify-self: end;
        flex-wrap: nowrap;
        overflow: hidden;
      }
      html[data-view="table"] .card[data-endpoint] .card-actions {
        width: 86px;
        justify-content: flex-end;
      }
      /* Table view is a compact scan mode: bodies stay in the cards view. */
      html[data-view="table"] .card[data-endpoint] .card-collapse { display: none; }
      html[data-view="table"] .card[data-endpoint] .chevron { visibility: hidden; }
      html[data-view="table"] .card[data-endpoint] button.card-toggle { cursor: default; }
      html[data-view="table"] .card[data-endpoint] button.card-toggle:hover { background: transparent; }
    }

    /* ===== Footer ================================================ */
    footer {
      border-top: 1px solid var(--line);
      padding: 2rem 0;
      margin-top: 1rem;
    }
    footer .container {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
      flex-wrap: wrap;
      color: var(--ink-3);
      font-family: var(--font-mono);
      font-size: 0.75rem;
    }
    footer a { color: var(--ink); text-decoration: none; border-bottom: 1px solid var(--line-2); }
    footer a:hover { border-bottom-color: var(--ink); }

    @media (max-width: 720px) {
      .summary { grid-template-columns: repeat(2, 1fr); }
      .summary-card:nth-child(3) { border-left: none; }
      .summary-card:nth-child(n+3) { border-top: 1px solid var(--line); }
      .header-tagline { display: none; }
    }

    @media (prefers-reduced-motion: reduce) {
      * { transition: none !important; scroll-behavior: auto !important; }
    }

    @media print {
      body { background: #fff; color: #000; }
      .report-header, footer { border-color: #ccc; }
      .card { break-inside: avoid; }
      .card.collapsed .card-collapse { grid-template-rows: 1fr; }
      .group.collapsed .group-body { display: block; }
      .chevron, .theme-toggle, .controls, .card-actions, .table-head { display: none; }
    }
    CSS
end
