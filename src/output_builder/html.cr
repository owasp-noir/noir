require "../models/output_builder"
require "../models/endpoint"
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
    String.build do |html|
      html << "<!DOCTYPE html>\n"
      html << "<html lang=\"en\">\n"
      html << build_head
      html << "<body>\n"
      html << build_header
      html << "<main class=\"container\">\n"
      html << build_summary(endpoints, passive_results)
      html << build_endpoints_section(endpoints)
      html << build_passive_results_section(passive_results)
      html << "</main>\n"
      html << build_footer
      html << "</body>\n"
      html << "</html>\n"
    end
  end

  private def build_head : String
    <<-HTML
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>OWASP Noir - Attack Surface Report</title>
      <style>
        :root {
          --primary-color: #2563eb;
          --primary-dark: #1d4ed8;
          --success-color: #22c55e;
          --warning-color: #f59e0b;
          --danger-color: #ef4444;
          --info-color: #3b82f6;
          --bg-color: #f8fafc;
          --card-bg: #ffffff;
          --text-color: #1e293b;
          --text-muted: #64748b;
          --border-color: #e2e8f0;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
          background-color: var(--bg-color);
          color: var(--text-color);
          line-height: 1.6;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 0 1rem; }
        header {
          background: linear-gradient(135deg, var(--primary-color), var(--primary-dark));
          color: white;
          padding: 2rem 0;
          margin-bottom: 2rem;
        }
        header h1 { font-size: 2rem; font-weight: 700; }
        header p { opacity: 0.9; margin-top: 0.5rem; }
        .summary {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 1rem;
          margin-bottom: 2rem;
        }
        .summary-card {
          background: var(--card-bg);
          border-radius: 0.5rem;
          padding: 1.5rem;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
          text-align: center;
        }
        .summary-card h3 { font-size: 2rem; font-weight: 700; }
        .summary-card p { color: var(--text-muted); font-size: 0.875rem; text-transform: uppercase; letter-spacing: 0.05em; }
        .summary-card.endpoints h3 { color: var(--primary-color); }
        .summary-card.passive h3 { color: var(--warning-color); }
        .summary-card.methods h3 { color: var(--success-color); }
        .summary-card.params h3 { color: var(--info-color); }
        .section { margin-bottom: 2rem; }
        .section-title {
          font-size: 1.5rem;
          font-weight: 600;
          margin-bottom: 1rem;
          padding-bottom: 0.5rem;
          border-bottom: 2px solid var(--border-color);
        }
        .card {
          background: var(--card-bg);
          border-radius: 0.5rem;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
          margin-bottom: 1rem;
          overflow: hidden;
        }
        .card-header {
          padding: 1rem;
          background: var(--bg-color);
          border-bottom: 1px solid var(--border-color);
          display: flex;
          align-items: center;
          gap: 0.75rem;
          flex-wrap: wrap;
        }
        .method-badge {
          display: inline-block;
          padding: 0.25rem 0.75rem;
          border-radius: 0.25rem;
          font-size: 0.75rem;
          font-weight: 700;
          text-transform: uppercase;
        }
        .method-get { background: #dcfce7; color: #166534; }
        .method-post { background: #dbeafe; color: #1e40af; }
        .method-put { background: #fef3c7; color: #92400e; }
        .method-patch { background: #fef3c7; color: #92400e; }
        .method-delete { background: #fee2e2; color: #991b1b; }
        .method-default { background: #f1f5f9; color: #475569; }
        .url { font-family: 'SF Mono', Monaco, 'Courier New', monospace; font-size: 0.9rem; word-break: break-all; }
        .protocol-badge {
          font-size: 0.7rem;
          padding: 0.15rem 0.5rem;
          border-radius: 0.25rem;
          background: #f1f5f9;
          color: var(--text-muted);
        }
        .card-body { padding: 1rem; }
        .params-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.875rem;
        }
        .params-table th, .params-table td {
          padding: 0.5rem;
          text-align: left;
          border-bottom: 1px solid var(--border-color);
        }
        .params-table th { background: var(--bg-color); font-weight: 600; }
        .param-type {
          display: inline-block;
          padding: 0.15rem 0.5rem;
          border-radius: 0.25rem;
          font-size: 0.7rem;
          font-weight: 600;
          text-transform: uppercase;
        }
        .param-query { background: #e0e7ff; color: #3730a3; }
        .param-json { background: #fef3c7; color: #92400e; }
        .param-form { background: #d1fae5; color: #065f46; }
        .param-header { background: #fce7f3; color: #9d174d; }
        .param-cookie { background: #ede9fe; color: #5b21b6; }
        .param-path { background: #cffafe; color: #0e7490; }
        .tag-badge {
          display: inline-block;
          padding: 0.15rem 0.5rem;
          border-radius: 0.25rem;
          font-size: 0.7rem;
          background: #f1f5f9;
          color: var(--text-muted);
          margin-right: 0.25rem;
        }
        .severity-critical, .severity-high { background: #fee2e2; color: #991b1b; }
        .severity-medium { background: #fef3c7; color: #92400e; }
        .severity-low { background: #d1fae5; color: #065f46; }
        .passive-card .card-header { border-left: 4px solid var(--warning-color); }
        .code-path {
          font-family: 'SF Mono', Monaco, 'Courier New', monospace;
          font-size: 0.8rem;
          color: var(--text-muted);
        }
        .empty-state {
          text-align: center;
          padding: 3rem;
          color: var(--text-muted);
        }
        footer {
          text-align: center;
          padding: 2rem;
          color: var(--text-muted);
          font-size: 0.875rem;
          border-top: 1px solid var(--border-color);
          margin-top: 2rem;
        }
        footer a { color: var(--primary-color); text-decoration: none; }
        footer a:hover { text-decoration: underline; }
        .collapsible { cursor: pointer; }
        .collapsible:hover { background: #f1f5f9; }
      </style>
    </head>

    HTML
  end

  private def build_header : String
    <<-HTML
    <header>
      <div class="container">
        <h1>OWASP Noir</h1>
        <p>Attack Surface Analysis Report</p>
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
      html << "<h2 class=\"section-title\">Discovered Endpoints</h2>\n"

      if endpoints.empty?
        html << "<div class=\"empty-state\"><p>No endpoints discovered.</p></div>\n"
      else
        endpoints.each do |endpoint|
          html << build_endpoint_card(endpoint)
        end
      end

      html << "</section>\n"
    end
  end

  private def build_endpoint_card(endpoint : Endpoint) : String
    baked = bake_endpoint(endpoint.url, endpoint.params)
    method_class = get_method_class(endpoint.method)

    String.build do |html|
      html << "<div class=\"card\">\n"
      html << "<div class=\"card-header collapsible\">\n"
      html << "<span class=\"method-badge #{method_class}\">#{HTML.escape(endpoint.method)}</span>\n"
      html << "<span class=\"url\">#{HTML.escape(baked[:url])}</span>\n"

      if endpoint.protocol != "http"
        html << "<span class=\"protocol-badge\">#{HTML.escape(endpoint.protocol)}</span>\n"
      end

      endpoint.tags.each do |tag|
        html << "<span class=\"tag-badge\">#{HTML.escape(tag.name)}</span>\n"
      end

      html << "</div>\n"

      if endpoint.params.size > 0 || !endpoint.details.code_paths.empty?
        html << "<div class=\"card-body\">\n"

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
              html << "<p class=\"code-path\">📁 #{HTML.escape(code_path.path)}</p>\n"
            else
              html << "<p class=\"code-path\">📁 #{HTML.escape(code_path.path)} (line #{code_path.line})</p>\n"
            end
          end
          html << "</div>\n"
        end

        html << "</div>\n"
      end

      html << "</div>\n"
    end
  end

  private def build_passive_results_section(passive_results : Array(PassiveScanResult)) : String
    String.build do |html|
      html << "<section class=\"section\">\n"
      html << "<h2 class=\"section-title\">Passive Scan Results</h2>\n"

      if passive_results.empty?
        html << "<div class=\"empty-state\"><p>No passive scan findings.</p></div>\n"
      else
        passive_results.each do |result|
          html << build_passive_result_card(result)
        end
      end

      html << "</section>\n"
    end
  end

  private def build_passive_result_card(result : PassiveScanResult) : String
    severity_class = get_severity_class(result.info.severity)

    String.build do |html|
      html << "<div class=\"card passive-card\">\n"
      html << "<div class=\"card-header\">\n"
      html << "<span class=\"method-badge #{severity_class}\">#{HTML.escape(result.info.severity.upcase)}</span>\n"
      html << "<span>#{HTML.escape(result.info.name)}</span>\n"
      html << "</div>\n"
      html << "<div class=\"card-body\">\n"
      html << "<p><strong>Description:</strong> #{HTML.escape(result.info.description)}</p>\n"
      html << "<p class=\"code-path\">📁 #{HTML.escape(result.file_path)} (line #{result.line_number})</p>\n"
      html << "<p><strong>Finding:</strong> <code>#{HTML.escape(result.extract)}</code></p>\n"
      html << "</div>\n"
      html << "</div>\n"
    end
  end

  private def build_footer : String
    <<-HTML
    <footer>
      <p>Generated by <a href="https://github.com/owasp-noir/noir" target="_blank">OWASP Noir</a></p>
    </footer>

    HTML
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
