require "../models/output_builder"
require "../models/endpoint"
require "../utils/home"
require "html"

class OutputBuilderHtml < OutputBuilder
  def print(endpoints : Array(Endpoint))
    html = build_html(endpoints, [] of PassiveScanResult)
    ob_puts html
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    html = build_html(endpoints, passive_results)
    ob_puts html
  end

  private def build_html(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult)) : String
    template_path = File.join(get_home, "report-template.html")

    if File.exists?(template_path)
      apply_template(template_path, endpoints, passive_results)
    else
      build_default_html(endpoints, passive_results)
    end
  end

  private def apply_template(template_path : String, endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult)) : String
    template = File.read(template_path)

    template = template.gsub("<%= noir_head %>", build_head)
    template = template.gsub("<%= noir_header %>", build_header)
    template = template.gsub("<%= noir_summary %>", build_summary(endpoints, passive_results))
    template = template.gsub("<%= noir_endpoints %>", build_endpoints_section(endpoints))
    template = template.gsub("<%= noir_passive_scans %>", build_passive_results_section(passive_results))
    template = template.gsub("<%= noir_footer %>", build_footer)
    template = template.gsub("<%= noir_scripts %>", build_scripts)

    template
  rescue
    # If template reading fails (permissions, encoding, corruption), fall back to default
    build_default_html(endpoints, passive_results)
  end

  private def build_default_html(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult)) : String
    String.build do |html|
      html << "<!DOCTYPE html>\n"
      html << "<html lang=\"en\">\n"
      html << "<head>\n"
      html << build_head
      html << "</head>\n"
      html << "<body>\n"
      html << build_header
      html << "<main class=\"container\">\n"
      html << build_summary(endpoints, passive_results)
      html << build_endpoints_section(endpoints)
      html << build_passive_results_section(passive_results)
      html << "</main>\n"
      html << build_footer
      html << build_scripts
      html << "</body>\n"
      html << "</html>\n"
    end
  end

  private def build_head : String
    <<-HTML
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="color-scheme" content="light dark">
        <title>OWASP Noir — Attack Surface Report</title>
        <style>
          /* ===== OWASP Noir — monochrome report theme =====================
             Ink-on-paper by default; true-black noir under [data-theme=dark].
             Pure grayscale: hierarchy comes from fill weight and hairlines,
             never from hue. */
          :root {
            --bg: #ffffff;
            --bg-subtle: #f6f6f6;
            --surface: #ffffff;
            --ink: #0a0a0a;
            --ink-2: #404040;
            --ink-3: #767676;
            --line: #e4e4e4;
            --line-2: #d0d0d0;
            --fill: #0a0a0a;
            --on-fill: #ffffff;
            --fill-mute: #555555;
            --hover: #f2f2f2;
            --selection: rgba(10, 10, 10, 0.12);
            --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            --font-mono: ui-monospace, "SF Mono", SFMono-Regular, "JetBrains Mono", Menlo, Consolas, "Liberation Mono", monospace;
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
            --on-fill: #050507;
            --fill-mute: #8a8a9c;
            --hover: #131319;
            --selection: rgba(237, 237, 240, 0.16);
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
          .container { max-width: 1140px; margin: 0 auto; padding: 0 1.5rem; }
          a { color: inherit; }

          /* ===== Header ================================================= */
          .report-header {
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
          .brand-mark rect.block { fill: var(--ink); }
          .brand-mark rect.visor { fill: var(--bg); }
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
            background: var(--ink);
            flex-shrink: 0;
          }
          .section-count {
            margin-left: auto;
            font-weight: 500;
            color: var(--ink-3);
            letter-spacing: 0.08em;
            font-variant-numeric: tabular-nums;
          }

          /* ===== Controls — search + filter chips ====================== */
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
          .search input:focus { outline: none; border-color: var(--ink); }
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

          /* ===== Cards ================================================== */
          .card {
            background: var(--surface);
            border: 1px solid var(--line);
            margin-bottom: -1px;
          }
          .card:hover { border-color: var(--line-2); position: relative; z-index: 1; }
          .card-header {
            padding: 0.85rem 1rem;
            display: flex;
            align-items: center;
            gap: 0.7rem;
            flex-wrap: wrap;
          }
          button.card-header {
            width: 100%;
            font: inherit;
            color: inherit;
            text-align: left;
            background: transparent;
            border: none;
            cursor: pointer;
            transition: background-color 0.12s ease;
          }
          button.card-header:hover { background: var(--hover); }
          button.card-header:focus-visible { outline: 2px solid var(--ink); outline-offset: -2px; }
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

          /* ===== Method badges — grayscale risk ramp ===================
             outline = safe read · gray = mutate · solid ink = destroy */
          .method-badge {
            display: inline-block;
            padding: 0.2rem 0.6rem;
            font-family: var(--font-mono);
            font-size: 0.7rem;
            font-weight: 700;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            border: 1px solid var(--ink);
            min-width: 4.6em;
            text-align: center;
            flex-shrink: 0;
          }
          .method-get { background: transparent; color: var(--ink); border-color: var(--line-2); }
          .method-post { background: var(--fill-mute); color: var(--on-fill); border-color: var(--fill-mute); }
          .method-put { background: var(--fill-mute); color: var(--on-fill); border-color: var(--fill-mute); }
          .method-patch { background: var(--fill-mute); color: var(--on-fill); border-color: var(--fill-mute); }
          .method-delete { background: var(--fill); color: var(--on-fill); border-color: var(--fill); }
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

          /* ===== Param-type chips — uniform monochrome ================= */
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

          /* ===== Severity badges — grayscale ramp ====================== */
          .severity-critical, .severity-high { background: var(--fill); color: var(--on-fill); border-color: var(--fill); }
          .severity-medium { background: var(--fill-mute); color: var(--on-fill); border-color: var(--fill-mute); }
          .severity-low { background: transparent; color: var(--ink); border-color: var(--line-2); }
          .passive-card .card-header { gap: 0.7rem; }

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
            .chevron, .theme-toggle, .controls { display: none; }
          }
        </style>
        <script>
          /* Apply the saved/preferred theme before first paint to avoid a flash. */
          (function () {
            try {
              var saved = localStorage.getItem("noir-theme");
              if (saved === "dark" || saved === "light") {
                document.documentElement.setAttribute("data-theme", saved);
              } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
                document.documentElement.setAttribute("data-theme", "dark");
              }
            } catch (e) {}
          })();
        </script>

      HTML
  end

  private def build_header : String
    <<-HTML
      <header class="report-header">
        <div class="container">
          <div class="brand">
            <svg class="brand-mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
              <rect class="block" x="2" y="4" width="20" height="16"></rect>
              <rect class="visor" x="5" y="10" width="14" height="3"></rect>
            </svg>
            <span class="brand-text">
              <span class="brand-eyebrow">OWASP</span>
              <span class="brand-title">Noir</span>
            </span>
          </div>
          <div class="header-actions">
            <span class="header-tagline">Attack Surface Report</span>
            <button type="button" class="theme-toggle" data-action="toggle-theme" aria-pressed="false" aria-label="Switch to dark theme" title="Toggle theme">
              <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">
                <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"></path>
              </svg>
              <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="square" aria-hidden="true">
                <circle cx="12" cy="12" r="4.2"></circle>
                <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1"></path>
              </svg>
            </button>
          </div>
        </div>
      </header>

      HTML
  end

  private def build_summary(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult)) : String
    methods = endpoints.map(&.method).uniq!.size
    total_params = endpoints.sum(&.params.size)

    <<-HTML
      <div class="summary">
        <div class="summary-card endpoints">
          <h3>#{endpoints.size}</h3>
          <p>Endpoints</p>
        </div>
        <div class="summary-card methods">
          <h3>#{methods}</h3>
          <p>HTTP Methods</p>
        </div>
        <div class="summary-card params">
          <h3>#{total_params}</h3>
          <p>Parameters</p>
        </div>
        <div class="summary-card passive">
          <h3>#{passive_results.size}</h3>
          <p>Passive Findings</p>
        </div>
      </div>

      HTML
  end

  private def build_endpoints_section(endpoints : Array(Endpoint)) : String
    String.build do |html|
      html << "<section class=\"section\">\n"
      html << "<h2 class=\"section-title\">Discovered Endpoints"
      unless endpoints.empty?
        html << " <span class=\"section-count\" id=\"endpoint-count\">#{endpoints.size}</span>"
      end
      html << "</h2>\n"

      if endpoints.empty?
        html << "<div class=\"empty-state\"><p>No endpoints discovered.</p></div>\n"
      else
        html << build_endpoint_controls(endpoints)
        endpoints.each_with_index do |endpoint, index|
          html << build_endpoint_card(endpoint, index)
        end
        html << "<div class=\"empty-state no-results\" id=\"endpoint-no-results\">No endpoints match the current filter.</div>\n"
      end

      html << "</section>\n"
    end
  end

  private def build_endpoint_controls(endpoints : Array(Endpoint)) : String
    methods = present_methods(endpoints)

    String.build do |html|
      html << "<div class=\"controls\">\n"
      html << "<div class=\"search\">\n"
      html << "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"square\" aria-hidden=\"true\"><circle cx=\"11\" cy=\"11\" r=\"7\"></circle><path d=\"M21 21l-4.3-4.3\"></path></svg>\n"
      html << "<input type=\"search\" id=\"endpoint-search\" placeholder=\"Filter by path, method, parameter, or tag…\" aria-label=\"Filter endpoints\" autocomplete=\"off\" spellcheck=\"false\">\n"
      html << "</div>\n"

      if methods.size > 1
        html << "<div class=\"chips\" role=\"group\" aria-label=\"Filter by HTTP method\">\n"
        methods.each do |method|
          html << "<button type=\"button\" class=\"chip\" data-filter-method=\"#{HTML.escape(method)}\" aria-pressed=\"false\">#{HTML.escape(method)}</button>\n"
        end
        html << "</div>\n"
      end

      html << "</div>\n"
    end
  end

  private def build_endpoint_card(endpoint : Endpoint, index : Int32) : String
    baked = bake_endpoint(endpoint.url, endpoint.params)
    method_class = get_method_class(endpoint.method)
    has_body = endpoint.params.size > 0 || !endpoint.details.code_paths.empty?
    search_text = endpoint_search_text(endpoint, baked[:url])
    body_id = "ep-body-#{index}"

    String.build do |html|
      html << "<div class=\"card\" data-endpoint data-method=\"#{HTML.escape(endpoint.method.upcase)}\" data-text=\"#{HTML.escape(search_text)}\">\n"

      if has_body
        html << "<button type=\"button\" class=\"card-header\" data-action=\"toggle-card\" aria-expanded=\"true\" aria-controls=\"#{body_id}\">\n"
        html << "<span class=\"chevron\" aria-hidden=\"true\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"square\"><path d=\"M6 9l6 6 6-6\"></path></svg></span>\n"
      else
        html << "<div class=\"card-header\">\n"
        html << "<span class=\"chevron-spacer\" aria-hidden=\"true\"></span>\n"
      end

      html << "<span class=\"method-badge #{method_class}\">#{HTML.escape(endpoint.method)}</span>\n"
      html << "<span class=\"url\">#{HTML.escape(baked[:url])}</span>\n"

      if endpoint.protocol != "http"
        html << "<span class=\"protocol-badge\">#{HTML.escape(endpoint.protocol)}</span>\n"
      end

      endpoint.tags.each do |tag|
        html << "<span class=\"tag-badge\">#{HTML.escape(tag.name)}</span>\n"
      end

      html << (has_body ? "</button>\n" : "</div>\n")

      if has_body
        html << "<div class=\"card-collapse\" id=\"#{body_id}\"><div class=\"card-pane\"><div class=\"card-body\">\n"

        if endpoint.params.size > 0
          html << "<table class=\"params-table\">\n"
          html << "<thead><tr><th>Parameter</th><th>Type</th><th>Value</th></tr></thead>\n"
          html << "<tbody>\n"

          endpoint.params.each do |param|
            param_class = get_param_class(param.param_type)
            html << "<tr>\n"
            html << "<td>#{HTML.escape(param.name)}</td>\n"
            html << "<td><span class=\"param-type #{param_class}\">#{HTML.escape(param.param_type)}</span></td>\n"
            html << "<td>#{HTML.escape(param.value)}</td>\n"
            html << "</tr>\n"
          end

          html << "</tbody>\n"
          html << "</table>\n"
        end

        if !endpoint.details.code_paths.empty?
          html << "<div style=\"margin-top: 0.5rem;\">\n"
          endpoint.details.code_paths.each do |code_path|
            if code_path.line.nil?
              html << "<p class=\"code-path\"><span class=\"marker\">&rarr;</span> #{HTML.escape(code_path.path)}</p>\n"
            else
              html << "<p class=\"code-path\"><span class=\"marker\">&rarr;</span> #{HTML.escape(code_path.path)} (line #{code_path.line})</p>\n"
            end
          end
          html << "</div>\n"
        end

        html << "</div></div></div>\n"
      end

      html << "</div>\n"
    end
  end

  private def build_passive_results_section(passive_results : Array(PassiveScanResult)) : String
    String.build do |html|
      html << "<section class=\"section\">\n"
      html << "<h2 class=\"section-title\">Passive Scan Results"
      unless passive_results.empty?
        html << " <span class=\"section-count\" id=\"passive-count\">#{passive_results.size}</span>"
      end
      html << "</h2>\n"

      if passive_results.empty?
        html << "<div class=\"empty-state\"><p>No passive scan findings.</p></div>\n"
      else
        html << build_passive_controls(passive_results)
        passive_results.each do |result|
          html << build_passive_result_card(result)
        end
        html << "<div class=\"empty-state no-results\" id=\"passive-no-results\">No findings match the current filter.</div>\n"
      end

      html << "</section>\n"
    end
  end

  private def build_passive_controls(passive_results : Array(PassiveScanResult)) : String
    severities = present_severities(passive_results)
    return "" if severities.size <= 1

    String.build do |html|
      html << "<div class=\"controls\">\n"
      html << "<div class=\"chips\" role=\"group\" aria-label=\"Filter by severity\">\n"
      severities.each do |severity|
        html << "<button type=\"button\" class=\"chip\" data-filter-severity=\"#{HTML.escape(severity)}\" aria-pressed=\"false\">#{HTML.escape(severity)}</button>\n"
      end
      html << "</div>\n"
      html << "</div>\n"
    end
  end

  private def build_passive_result_card(result : PassiveScanResult) : String
    severity_class = get_severity_class(result.info.severity)

    String.build do |html|
      html << "<div class=\"card passive-card\" data-passive data-severity=\"#{HTML.escape(result.info.severity.downcase)}\">\n"
      html << "<div class=\"card-header\">\n"
      html << "<span class=\"method-badge #{severity_class}\">#{HTML.escape(result.info.severity.upcase)}</span>\n"
      html << "<span>#{HTML.escape(result.info.name)}</span>\n"
      html << "</div>\n"
      html << "<div class=\"card-body\">\n"
      html << "<p><strong>Description:</strong> #{HTML.escape(result.info.description)}</p>\n"
      html << "<p class=\"code-path\"><span class=\"marker\">&rarr;</span> #{HTML.escape(result.file_path)} (line #{result.line_number})</p>\n"
      html << "<p><strong>Finding:</strong> <code>#{HTML.escape(result.extract)}</code></p>\n"
      html << "</div>\n"
      html << "</div>\n"
    end
  end

  private def build_footer : String
    <<-HTML
      <footer>
        <div class="container">
          <span>Generated by <a href="https://github.com/owasp-noir/noir" target="_blank" rel="noopener">OWASP Noir</a></span>
          <span>Hunt every Endpoint · Map the Attack Surface</span>
        </div>
      </footer>

      HTML
  end

  private def build_scripts : String
    <<-HTML
      <script>
        (function () {
          var root = document.documentElement;

          function toArray(nodes) { return Array.prototype.slice.call(nodes); }

          // Reflect the active theme on the toggle control (a11y state).
          function syncThemeButtons() {
            var dark = root.getAttribute("data-theme") === "dark";
            toArray(document.querySelectorAll('[data-action="toggle-theme"]')).forEach(function (b) {
              b.setAttribute("aria-pressed", String(dark));
              b.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
            });
          }
          syncThemeButtons();

          // Theme toggle with persistence (initial theme is set in <head>).
          document.addEventListener("click", function (e) {
            var btn = e.target.closest && e.target.closest('[data-action="toggle-theme"]');
            if (!btn) return;
            var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
            root.setAttribute("data-theme", next);
            try { localStorage.setItem("noir-theme", next); } catch (err) {}
            syncThemeButtons();
          });

          // Collapse / expand an endpoint card.
          document.addEventListener("click", function (e) {
            var header = e.target.closest && e.target.closest('[data-action="toggle-card"]');
            if (!header) return;
            var card = header.closest(".card");
            if (!card) return;
            var collapsed = card.classList.toggle("collapsed");
            header.setAttribute("aria-expanded", String(!collapsed));
          });

          // Endpoint search + HTTP-method chip filter (combined with AND).
          var search = document.getElementById("endpoint-search");
          var methodChips = toArray(document.querySelectorAll("[data-filter-method]"));
          var endpointCards = toArray(document.querySelectorAll("[data-endpoint]"));
          var endpointCount = document.getElementById("endpoint-count");
          var endpointEmpty = document.getElementById("endpoint-no-results");

          function applyEndpointFilter() {
            var q = (search ? search.value : "").trim().toLowerCase();
            var active = methodChips
              .filter(function (c) { return c.getAttribute("aria-pressed") === "true"; })
              .map(function (c) { return c.getAttribute("data-filter-method"); });
            var shown = 0;
            endpointCards.forEach(function (card) {
              var okText = !q || (card.getAttribute("data-text") || "").indexOf(q) !== -1;
              var okMethod = active.length === 0 || active.indexOf(card.getAttribute("data-method")) !== -1;
              var visible = okText && okMethod;
              card.hidden = !visible;
              if (visible) shown++;
            });
            if (endpointCount) {
              endpointCount.textContent = shown === endpointCards.length ? String(shown) : shown + " / " + endpointCards.length;
            }
            if (endpointEmpty) endpointEmpty.classList.toggle("show", shown === 0);
          }

          if (search) search.addEventListener("input", applyEndpointFilter);
          methodChips.forEach(function (chip) {
            chip.addEventListener("click", function () {
              chip.setAttribute("aria-pressed", chip.getAttribute("aria-pressed") === "true" ? "false" : "true");
              applyEndpointFilter();
            });
          });

          // Passive-finding severity chip filter.
          var sevChips = toArray(document.querySelectorAll("[data-filter-severity]"));
          var passiveCards = toArray(document.querySelectorAll("[data-passive]"));
          var passiveCount = document.getElementById("passive-count");
          var passiveEmpty = document.getElementById("passive-no-results");

          function applyPassiveFilter() {
            var active = sevChips
              .filter(function (c) { return c.getAttribute("aria-pressed") === "true"; })
              .map(function (c) { return c.getAttribute("data-filter-severity"); });
            var shown = 0;
            passiveCards.forEach(function (card) {
              var visible = active.length === 0 || active.indexOf(card.getAttribute("data-severity")) !== -1;
              card.hidden = !visible;
              if (visible) shown++;
            });
            if (passiveCount) {
              passiveCount.textContent = shown === passiveCards.length ? String(shown) : shown + " / " + passiveCards.length;
            }
            if (passiveEmpty) passiveEmpty.classList.toggle("show", shown === 0);
          }

          sevChips.forEach(function (chip) {
            chip.addEventListener("click", function () {
              chip.setAttribute("aria-pressed", chip.getAttribute("aria-pressed") === "true" ? "false" : "true");
              applyPassiveFilter();
            });
          });
        })();
      </script>

      HTML
  end

  # Lowercased haystack used by the client-side endpoint filter.
  private def endpoint_search_text(endpoint : Endpoint, url : String) : String
    String.build do |s|
      s << endpoint.method.downcase << ' ' << url.downcase
      endpoint.params.each { |p| s << ' ' << p.name.downcase << ' ' << p.param_type.downcase }
      endpoint.tags.each { |t| s << ' ' << t.name.downcase }
      s << ' ' << endpoint.protocol.downcase unless endpoint.protocol == "http"
    end
  end

  # Distinct HTTP methods present, ordered by a canonical verb priority.
  private def present_methods(endpoints : Array(Endpoint)) : Array(String)
    order = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    methods = endpoints.map(&.method.upcase).uniq!
    methods.sort_by! { |m| {order.index(m) || order.size, m} }
  end

  # Distinct severities present, ordered from most to least severe.
  private def present_severities(passive_results : Array(PassiveScanResult)) : Array(String)
    order = ["critical", "high", "medium", "low", "info"]
    severities = passive_results.map(&.info.severity.downcase).uniq!
    severities.sort_by! { |s| {order.index(s) || order.size, s} }
  end

  private def get_method_class(method : String) : String
    case method.upcase
    when "GET"    then "method-get"
    when "POST"   then "method-post"
    when "PUT"    then "method-put"
    when "PATCH"  then "method-patch"
    when "DELETE" then "method-delete"
    else               "method-default"
    end
  end

  private def get_param_class(param_type : String) : String
    case param_type
    when "query"  then "param-query"
    when "json"   then "param-json"
    when "form"   then "param-form"
    when "header" then "param-header"
    when "cookie" then "param-cookie"
    when "path"   then "param-path"
    else               ""
    end
  end

  private def get_severity_class(severity : String) : String
    case severity.downcase
    when "critical", "high" then "severity-critical"
    when "medium"           then "severity-medium"
    when "low"              then "severity-low"
    else                         ""
    end
  end
end
