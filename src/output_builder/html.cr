require "../models/output_builder"
require "../models/endpoint"
require "../utils/home"
require "../utils/http_symbols"
require "../utils/curl_command"
require "./html_assets/css"
require "./html_assets/js"
require "./html_assets/logo"
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
    String.build do |html|
      html << "<meta charset=\"UTF-8\">\n"
      html << "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
      html << "<meta name=\"color-scheme\" content=\"light dark\">\n"
      html << "<title>OWASP Noir · Attack Surface Report</title>\n"
      html << "<style>\n" << HtmlReportAssets::STYLES << "\n</style>\n"
      html << "<script>\n" << HtmlReportAssets::THEME_BOOT << "\n</script>\n"
    end
  end

  private def build_header : String
    <<-HTML
      <header class="report-header">
        <div class="container">
          <div class="brand">
            <img class="brand-mark" src="data:image/png;base64,#{HtmlReportAssets::LOGO_PNG_BASE64}" alt="" width="38" height="38">
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
        groups = group_endpoints(endpoints)
        grouped = groups.size >= 2 && groups.size < endpoints.size

        html << build_endpoint_controls(endpoints, grouped)
        html << build_table_head
        html << "<div class=\"visually-hidden\" id=\"copy-status\" aria-live=\"polite\"></div>\n"

        index = 0
        if grouped
          groups.each do |key, group_members|
            html << "<div class=\"group\" data-group-key=\"#{HTML.escape(key)}\">\n"
            html << "<button type=\"button\" class=\"group-header\" data-action=\"toggle-group-collapse\" aria-expanded=\"true\">\n"
            html << "<span class=\"chevron\" aria-hidden=\"true\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"square\"><path d=\"M6 9l6 6 6-6\"></path></svg></span>\n"
            html << "<span class=\"group-name\">#{HTML.escape(key)}</span>\n"
            html << "<span class=\"group-count\" data-group-count>#{group_members.size}</span>\n"
            html << "</button>\n"
            html << "<div class=\"group-body\">\n"
            group_members.each do |endpoint|
              html << build_endpoint_card(endpoint, index)
              index += 1
            end
            html << "</div>\n"
            html << "</div>\n"
          end
        else
          endpoints.each do |endpoint|
            html << build_endpoint_card(endpoint, index)
            index += 1
          end
        end

        html << "<div class=\"empty-state no-results\" id=\"endpoint-no-results\">No endpoints match the current filter.</div>\n"
      end

      html << "</section>\n"
    end
  end

  private def build_endpoint_controls(endpoints : Array(Endpoint), grouped : Bool) : String
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
          html << "<button type=\"button\" class=\"chip#{chip_hue_class(method)}\" data-filter-method=\"#{HTML.escape(method)}\" aria-pressed=\"false\">#{HTML.escape(method)}</button>\n"
        end
        html << "</div>\n"
      end

      if grouped
        html << "<button type=\"button\" class=\"chip group-toggle\" data-action=\"toggle-group\" aria-pressed=\"true\">Grouped</button>\n"
      end

      html << "<div class=\"view-seg\" role=\"group\" aria-label=\"Result layout\">\n"
      html << "<button type=\"button\" class=\"view-btn\" data-action=\"set-view\" data-view-mode=\"cards\" aria-pressed=\"true\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" aria-hidden=\"true\"><rect x=\"3\" y=\"4\" width=\"18\" height=\"7\"></rect><rect x=\"3\" y=\"14\" width=\"18\" height=\"7\"></rect></svg>Cards</button>\n"
      html << "<button type=\"button\" class=\"view-btn\" data-action=\"set-view\" data-view-mode=\"table\" aria-pressed=\"false\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" aria-hidden=\"true\"><path d=\"M3 6h18M3 12h18M3 18h18\"></path></svg>Table</button>\n"
      html << "</div>\n"

      html << "</div>\n"
    end
  end

  private def build_table_head : String
    String.build do |html|
      html << "<div class=\"table-head\" aria-hidden=\"true\">\n"
      html << "<span></span>\n"
      html << "<span>Method</span>\n"
      html << "<span>Path</span>\n"
      html << "<span class=\"th-details\">Details</span>\n"
      html << "</div>\n"
    end
  end

  private def build_endpoint_card(endpoint : Endpoint, index : Int32) : String
    baked = bake_endpoint(endpoint.url, endpoint.params)
    method_class = get_method_class(endpoint.method)
    has_body = endpoint.params.size > 0 || !endpoint.details.code_paths.empty?
    search_text = endpoint_search_text(endpoint, baked[:url])
    body_id = "ep-body-#{index}"
    curl = curl_attribute_for(endpoint, baked)

    String.build do |html|
      html << "<div class=\"card\" data-endpoint data-method=\"#{HTML.escape(endpoint.method.upcase)}\" data-text=\"#{HTML.escape(search_text)}\" data-url=\"#{HTML.escape(baked[:url])}\""
      html << " data-curl=\"#{HTML.escape(curl)}\"" if curl
      html << ">\n"
      html << "<div class=\"card-header\">\n"

      if has_body
        html << "<button type=\"button\" class=\"card-toggle\" data-action=\"toggle-card\" aria-expanded=\"true\" aria-controls=\"#{body_id}\">\n"
        html << "<span class=\"chevron\" aria-hidden=\"true\"><svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" stroke-linecap=\"square\"><path d=\"M6 9l6 6 6-6\"></path></svg></span>\n"
      else
        html << "<div class=\"card-toggle\">\n"
        html << "<span class=\"chevron-spacer\" aria-hidden=\"true\"></span>\n"
      end

      html << "<span class=\"method-badge #{method_class}\">#{HTML.escape(endpoint.method)}</span>\n"
      html << "<span class=\"url\">#{HTML.escape(baked[:url])}</span>\n"

      if endpoint.protocol != "http" || !endpoint.tags.empty? || endpoint.params.size > 0
        html << "<span class=\"card-details\">\n"
        if endpoint.protocol != "http"
          html << "<span class=\"protocol-badge\">#{HTML.escape(endpoint.protocol)}</span>\n"
        end
        endpoint.tags.each do |tag|
          html << "<span class=\"tag-badge\">#{HTML.escape(tag.name)}</span>\n"
        end
        if endpoint.params.size > 0
          html << "<span class=\"card-meta\">#{endpoint.params.size} #{endpoint.params.size == 1 ? "param" : "params"}</span>\n"
        end
        html << "</span>\n"
      end

      html << (has_body ? "</button>\n" : "</div>\n")

      html << "<span class=\"card-actions\">\n"
      html << "<button type=\"button\" class=\"copy-btn\" data-action=\"copy-url\" aria-label=\"Copy URL\" title=\"Copy URL\">"
      html << "<svg class=\"icon-copy\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" aria-hidden=\"true\"><rect x=\"9\" y=\"9\" width=\"11\" height=\"11\"></rect><path d=\"M5 15V4h11\"></path></svg>"
      html << "<svg class=\"icon-check\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" aria-hidden=\"true\"><path d=\"M4 12l5 5L20 6\"></path></svg>"
      html << "</button>\n"
      if curl
        html << "<button type=\"button\" class=\"copy-btn\" data-action=\"copy-curl\" aria-label=\"Copy as curl\" title=\"Copy as curl\">"
        html << "<svg class=\"icon-copy\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" aria-hidden=\"true\"><path d=\"M4 6l6 6-6 6M13 18h7\"></path></svg>"
        html << "<svg class=\"icon-check\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\" aria-hidden=\"true\"><path d=\"M4 12l5 5L20 6\"></path></svg>"
        html << "</button>\n"
      end
      html << "</span>\n"
      html << "</div>\n"

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
        html << "<button type=\"button\" class=\"chip#{chip_hue_class(severity)}\" data-filter-severity=\"#{HTML.escape(severity)}\" aria-pressed=\"false\">#{HTML.escape(severity)}</button>\n"
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
    String.build do |html|
      html << "<script>\n" << HtmlReportAssets::SCRIPTS << "\n</script>\n"
    end
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

  # Newline-separated curl commands for the copy-as-curl button, or nil for
  # non-HTTP endpoints (mobile deep links / CLI commands).
  private def curl_attribute_for(endpoint : Endpoint, baked) : String?
    return if endpoint.non_http?

    expand_synthetic_http_methods(endpoint.method).join("\n") do |method|
      CurlCommand.build(method, baked[:url], baked[:body], baked[:body_type], baked[:header], baked[:cookie])
    end
  end

  # Bucket key for the path-grouped endpoint list: authority plus first path
  # segment for absolute URLs, "/" plus first segment for relative paths.
  private def endpoint_group_key(endpoint : Endpoint) : String
    path = endpoint.url.split('?', 2)[0]

    if match = path.match(%r{\A([a-z][a-z0-9+.\-]*://[^/]*)(/.*)?}i)
      head = match[1]
      first = match[2]?.try(&.split('/').reject(&.empty?).first?)
      first ? "#{head}/#{first}" : head
    elsif path.starts_with?("//")
      authority, _, tail = path[2..].partition('/')
      first = tail.split('/').reject(&.empty?).first?
      first ? "//#{authority}/#{first}" : "//#{authority}"
    else
      first = path.split('/').reject(&.empty?).first?
      first ? "/#{first}" : "/"
    end
  end

  # Ordered grouping that preserves within-group input order. Roots and
  # relative paths sort alphabetically first; absolute URLs sort last.
  private def group_endpoints(endpoints : Array(Endpoint)) : Array(Tuple(String, Array(Endpoint)))
    order = [] of String
    buckets = Hash(String, Array(Endpoint)).new
    endpoints.each do |endpoint|
      key = endpoint_group_key(endpoint)
      unless buckets.has_key?(key)
        order << key
        buckets[key] = [] of Endpoint
      end
      buckets[key] << endpoint
    end
    order.sort_by! do |key|
      remote = key.includes?("://") || key.starts_with?("//") ? 1 : 0
      {remote, key == "/" ? "" : key.downcase}
    end
    order.map { |key| {key, buckets[key]} }
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

  # Hue modifier for pressed filter chips; only known verbs/severities get one.
  private def chip_hue_class(name : String) : String
    case name.downcase
    when "get", "post", "put", "patch", "delete",
         "critical", "high", "medium", "low"
      " chip-#{name.downcase}"
    else
      ""
    end
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
    when "critical" then "severity-critical"
    when "high"     then "severity-high"
    when "medium"   then "severity-medium"
    when "low"      then "severity-low"
    else                 "severity-info"
    end
  end
end
