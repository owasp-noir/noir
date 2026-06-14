require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "xml"

module Analyzer::Java
  class Jsp < Analyzer
    alias ServletClassKey = Tuple(String, String)

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The `doGet`/`doPost`/... probe set is
    # fixed, so precompile it once at load time.
    SERVLET_DO_METHOD_PATTERNS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
    }.map do |suffix, method|
      {method, /\bvoid\s+do#{suffix}\s*\(([^)]*)\)\s*(?:throws[^{]+)?\{/m}
    end

    # The request-access matchers interpolate a discovered receiver name, so
    # they can't be hoisted — memoize them per receiver instead of rebuilding
    # four regexes for every handler body.
    @servlet_param_regexes = Hash(String, Tuple(Regex, Regex, Regex, Regex)).new

    def analyze
      servlet_methods = collect_servlet_methods

      # Source Analysis
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            all_files.each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  relative_path = get_relative_path(configured_base_for(path), path)

                  if File.exists?(path) && File.extname(path) == ".jsp"
                    next if web_inf_jsp?(relative_path)

                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      content = file.gets_to_end
                      params_query = extract_params(content)
                      details = Details.new(PathInfo.new(path))
                      result << Endpoint.new(jsp_request_path(relative_path), "GET", params_query, details)
                      extract_form_endpoints(content, details).each do |endpoint|
                        result << endpoint
                      end
                    end
                  elsif File.exists?(path) && File.extname(path) == ".java"
                    content = read_file_content(path)
                    details = Details.new(PathInfo.new(path))
                    extract_web_servlet_endpoints(content, details).each do |endpoint|
                      result << endpoint
                    end
                  elsif File.exists?(path) && File.basename(path) == "web.xml"
                    content = read_file_content(path)
                    details = Details.new(PathInfo.new(path))
                    extract_web_xml_endpoints(content, servlet_methods, details, configured_base_for(path)).each do |endpoint|
                      result << endpoint
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      Fiber.yield

      result
    end

    def allow_patterns
      ["request.getParameter", "request.getAttribute", "request.getHeader", "request.getCookies", "${param.", "${param[", "${paramValues.", "${cookie.", "@WebServlet", "<servlet-mapping>"]
    end

    private def collect_servlet_methods : Hash(ServletClassKey, Hash(String, Array(Param)))
      servlet_methods = Hash(ServletClassKey, Hash(String, Array(Param))).new

      all_files.each do |path|
        next unless File.extname(path) == ".java"

        content = read_file_content(path)
        next unless servlet_source?(content)

        methods = extract_servlet_http_methods(content)
        next if methods.empty?

        if class_name = java_class_name(content)
          base_path = configured_base_for(path)
          servlet_methods[{base_path, class_name}] = methods
          if package_name = java_package_name(content)
            servlet_methods[{base_path, "#{package_name}.#{class_name}"}] = methods
          end
        end
      rescue File::NotFoundError
        logger.debug "File not found: #{path}"
      end

      servlet_methods
    end

    # Container- and framework-managed request attributes. These are
    # populated by the servlet engine, filters or the MVC layer — never
    # by user input — so `request.getAttribute("javax.servlet....")`
    # must not be reported as a request parameter.
    INTERNAL_ATTRIBUTE_PREFIXES = [
      "javax.servlet.", "jakarta.servlet.",
      "javax.faces.", "jakarta.faces.",
      "org.springframework.", "org.apache.",
      "org.eclipse.jetty.", "org.glassfish.",
      "com.sun.", "weblogic.", "io.undertow.",
    ]

    def internal_servlet_attribute?(name : String) : Bool
      INTERNAL_ATTRIBUTE_PREFIXES.any? { |prefix| name.starts_with?(prefix) }
    end

    def extract_params(content : String) : Array(Param)
      params = [] of Param

      content.scan(/request\s*\.\s*get(?:Parameter|ParameterValues)\s*\(\s*["']([^"']+)["']\s*\)/) do |match|
        add_param(params, match[1], "query")
      end

      content.scan(/request\s*\.\s*getAttribute\s*\(\s*["']([^"']+)["']\s*\)/) do |match|
        next if internal_servlet_attribute?(match[1])
        add_param(params, match[1], "query")
      end

      content.scan(/request\s*\.\s*getHeaders?\s*\(\s*["']([^"']+)["']\s*\)/) do |match|
        add_param(params, match[1], "header")
      end

      add_param(params, "", "cookie") if content.match(/request\s*\.\s*getCookies\s*\(/)

      content.scan(/\$\{\s*param(?:Values)?\.([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        add_param(params, match[1], "query")
      end

      content.scan(/\$\{\s*param(?:Values)?\s*\[\s*["']([^"']+)["']\s*\]/) do |match|
        add_param(params, match[1], "query")
      end

      content.scan(/\$\{\s*cookie\.([A-Za-z_][A-Za-z0-9_-]*)/) do |match|
        add_param(params, match[1], "cookie")
      end

      content.scan(/\$\{\s*cookie\s*\[\s*["']([^"']+)["']\s*\]/) do |match|
        add_param(params, match[1], "cookie")
      end

      params
    end

    private def extract_form_endpoints(content : String, details : Details) : Array(Endpoint)
      endpoints = [] of Endpoint

      content.scan(/<form\b([^>]*)>(.*?)<\/form>/im) do |match|
        attrs = html_attrs(match[1])
        action = normalized_form_action(attrs["action"]?)
        next unless action

        method = (attrs["method"]? || "GET").upcase
        method = "GET" unless %w[GET POST PUT DELETE PATCH].includes?(method)
        params = extract_form_params(match[2], method)

        next if endpoints.any? { |endpoint| endpoint.url == action && endpoint.method == method }

        endpoints << Endpoint.new(action, method, params, details)
      end

      endpoints
    end

    private def extract_web_servlet_endpoints(content : String, details : Details) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless content.includes?("@WebServlet")

      methods = extract_servlet_http_methods(content)
      return endpoints if methods.empty?

      content_without_comments(content).scan(/@WebServlet\s*(?:\((.*?)\))?\s*(?:public\s+|protected\s+|private\s+)?(?:final\s+|abstract\s+)?class\s+\w+/m) do |match|
        annotation_body = match[1]? || ""
        extract_servlet_url_patterns(annotation_body).each do |pattern|
          methods.each do |method, params|
            add_endpoint(endpoints, pattern, method, params, details)
          end
        end
      end

      endpoints
    end

    private def extract_web_xml_endpoints(content : String,
                                          servlet_methods : Hash(ServletClassKey, Hash(String, Array(Param))),
                                          details : Details,
                                          base_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      doc = XML.parse(content)
      servlet_classes = Hash(String, String).new
      jsp_servlets = Set(String).new

      doc.xpath_nodes("//*[local-name()='servlet']").each do |servlet|
        name = xml_child_text(servlet, "servlet-name")
        next if name.empty?

        jsp_file = xml_child_text(servlet, "jsp-file")
        if !jsp_file.empty?
          jsp_servlets << name
          next
        end

        servlet_class = xml_child_text(servlet, "servlet-class")
        unless servlet_class.empty?
          servlet_classes[name] = servlet_class
        end
      end

      doc.xpath_nodes("//*[local-name()='servlet-mapping']").each do |mapping|
        name = xml_child_text(mapping, "servlet-name")
        next if name.empty?

        patterns = mapping.xpath_nodes("./*[local-name()='url-pattern']").map(&.content.strip).reject(&.empty?)
        next if patterns.empty?

        if jsp_servlets.includes?(name)
          patterns.each { |pattern| add_endpoint(endpoints, normalize_servlet_pattern(pattern), "GET", [] of Param, details) }
          next
        end

        servlet_class = servlet_classes[name]?
        next unless servlet_class

        methods = methods_for_servlet_class(servlet_class, servlet_methods, base_path)
        next unless methods

        patterns.each do |pattern|
          methods.each do |method, params|
            add_endpoint(endpoints, normalize_servlet_pattern(pattern), method, params, details)
          end
        end
      end

      endpoints
    rescue XML::Error
      [] of Endpoint
    end

    private def methods_for_servlet_class(servlet_class : String,
                                          servlet_methods : Hash(ServletClassKey, Hash(String, Array(Param))),
                                          base_path : String) : Hash(String, Array(Param))?
      simple_name = servlet_class.split(".").last
      methods = servlet_methods[{base_path, servlet_class}]? || servlet_methods[{base_path, simple_name}]?
      return methods if methods

      all_files.each do |path|
        # Cheap basename gate first; only resolve the configured base (which
        # expands paths) for the rare files whose name actually matches.
        next unless File.basename(path, ".java") == simple_name
        next unless configured_base_for(path) == base_path

        content = read_file_content(path)
        methods = extract_servlet_http_methods(content)
        return methods unless methods.empty?
      rescue File::NotFoundError
        logger.debug "File not found: #{path}"
      end
    end

    private def extract_servlet_http_methods(content : String) : Hash(String, Array(Param))
      methods = Hash(String, Array(Param)).new

      SERVLET_DO_METHOD_PATTERNS.each do |method, pattern|
        if match = content.match(pattern)
          request_receivers = servlet_request_receivers(match[1])
          body = extract_balanced_block(content, (match.end(0) || 1) - 1)
          methods[method] = extract_servlet_params(body, method, request_receivers)
        end
      end

      methods
    end

    private def servlet_request_receivers(signature : String) : Array(String)
      receivers = ["request"]
      signature.scan(/(?:^|,)\s*(?:final\s+)?(?:(?:jakarta|javax)\s*\.\s*servlet\s*\.\s*http\s*\.\s*)?HttpServletRequest\s+([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        receivers << match[1]
      end
      receivers.uniq
    end

    private def extract_servlet_params(content : String, method : String, request_receivers : Array(String)) : Array(Param)
      params = [] of Param
      request_param_type = method == "GET" ? "query" : "form"

      request_receivers.each do |receiver|
        parameter_re, attribute_re, header_re, cookie_re = @servlet_param_regexes[receiver] ||= begin
          receiver_pattern = Regex.escape(receiver)
          {/#{receiver_pattern}\s*\.\s*get(?:Parameter|ParameterValues)\s*\(\s*["']([^"']+)["']\s*\)/,
           /#{receiver_pattern}\s*\.\s*getAttribute\s*\(\s*["']([^"']+)["']\s*\)/,
           /#{receiver_pattern}\s*\.\s*getHeaders?\s*\(\s*["']([^"']+)["']\s*\)/,
           /#{receiver_pattern}\s*\.\s*getCookies\s*\(/}
        end

        content.scan(parameter_re) do |match|
          add_param(params, match[1], request_param_type)
        end

        content.scan(attribute_re) do |match|
          next if internal_servlet_attribute?(match[1])
          add_param(params, match[1], request_param_type)
        end

        content.scan(header_re) do |match|
          add_param(params, match[1], "header")
        end

        add_param(params, "", "cookie") if content.match(cookie_re)
      end

      params
    end

    private def extract_servlet_url_patterns(annotation_body : String) : Array(String)
      patterns = [] of String
      body = annotation_body.strip

      # `initParams = {@WebInitParam(name="x", value="y"), ...}` nests its
      # own `value=` attributes that are init-param values, NOT URL
      # patterns. Strip the block before scanning so a
      # `@WebInitParam(value="Not provided")` can't surface as a
      # `/Not provided` route.
      body = body.gsub(/\binitParams\s*=\s*\{[^}]*\}/m, "")

      if body.starts_with?("\"") || body.starts_with?("'") || body.starts_with?("{")
        body.scan(/["']([^"']+)["']/) do |match|
          add_pattern(patterns, match[1])
        end
        return patterns
      end

      body.scan(/(?:value|urlPatterns)\s*=\s*(?:\{([^}]*)\}|(["'][^"']+["']))/m) do |match|
        source = match[1]? || match[2]? || ""
        source.scan(/["']([^"']+)["']/) do |string_match|
          add_pattern(patterns, string_match[1])
        end
      end

      patterns
    end

    private def extract_form_params(form_body : String, method : String) : Array(Param)
      params = [] of Param
      param_type = method == "GET" ? "query" : "form"

      form_body.scan(/<(?:input|select|textarea)\b([^>]*)>/im) do |match|
        attrs = html_attrs(match[1])
        name = attrs["name"]?
        next if name.nil? || name.empty?

        add_param(params, name, param_type)
      end

      params
    end

    private def normalized_form_action(raw_action : String?) : String?
      return unless raw_action

      action = html_attr_decode(raw_action.strip)
      return if action.empty? || action.starts_with?("#")
      return if action.match(/\A(?:https?:|mailto:|javascript:)/i)

      if c_url = action.match(/<c:url\s+[^>]*value=["']([^"']+)["'][^>]*\/?>/i)
        action = c_url[1]
      end

      action = action.gsub(/\$\{\s*(?:pageContext\.request\.contextPath|request\.contextPath|contextPath)\s*\}/, "")
      return unless action.starts_with?("/")

      action
    end

    private def servlet_source?(content : String) : Bool
      content.includes?("@WebServlet") ||
        (content.includes?("HttpServlet") && !!content.match(/\bextends\s+HttpServlet\b/))
    end

    private def java_class_name(content : String) : String?
      if match = content.match(/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)/)
        match[1]
      end
    end

    private def java_package_name(content : String) : String?
      if match = content.match(/\bpackage\s+([A-Za-z_][A-Za-z0-9_.]*)\s*;/)
        match[1]
      end
    end

    private def content_without_comments(content : String) : String
      content
        .gsub(/\/\*.*?\*\//m, "")
        .gsub(/\/\/.*$/, "")
    end

    private def extract_balanced_block(content : String, open_index : Int32) : String
      depth = 0
      i = open_index

      while i < content.size
        case content[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          return content[open_index..i] if depth == 0
        end

        i += 1
      end

      content[open_index..]
    end

    private def web_inf_jsp?(relative_path : String) : Bool
      relative_path.split(File::SEPARATOR).includes?("WEB-INF")
    end

    # A JSP is served relative to the WEB application root, not the repo
    # root. `src/main/webapp/jsp/index.jsp` is reachable at `/jsp/index.jsp`,
    # so strip the build-layout webapp-root prefix; otherwise the whole
    # source path (`/libraries-otel/.../src/main/webapp/index.jsp`) leaked
    # into the URL.
    WEBAPP_ROOT_MARKERS = ["src/main/webapp/", "src/main/resources/META-INF/resources/", "WebContent/", "WebRoot/"]

    private def jsp_request_path(relative_path : String) : String
      normalized = relative_path.gsub(File::SEPARATOR, "/")
      WEBAPP_ROOT_MARKERS.each do |marker|
        if idx = normalized.index(marker)
          return "/#{normalized[(idx + marker.size)..]}"
        end
      end
      "/#{normalized}"
    end

    private def xml_child_text(node : XML::Node, local_name : String) : String
      child = node.xpath_node("./*[local-name()='#{local_name}']")
      child ? child.content.strip : ""
    end

    private def normalize_servlet_pattern(pattern : String) : String
      normalized = html_attr_decode(pattern.strip)
      return "/" if normalized.empty?
      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    private def add_pattern(patterns : Array(String), pattern : String)
      normalized = normalize_servlet_pattern(pattern)
      return unless normalized.starts_with?("/")
      return if patterns.includes?(normalized)

      patterns << normalized
    end

    private def add_endpoint(endpoints : Array(Endpoint), path : String, method : String, params : Array(Param), details : Details)
      return if endpoints.any? { |endpoint| endpoint.url == path && endpoint.method == method }

      endpoints << Endpoint.new(path, method, params, details)
    end

    private def html_attrs(source : String) : Hash(String, String)
      attrs = Hash(String, String).new

      source.scan(/([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/) do |match|
        next if match.size < 5

        key = match[1].downcase
        value = match[2]? || match[3]? || match[4]? || ""
        attrs[key] = html_attr_decode(value)
      end

      attrs
    end

    private def html_attr_decode(value : String) : String
      value
        .gsub("&amp;", "&")
        .gsub("&quot;", "\"")
        .gsub("&#39;", "'")
        .gsub("&apos;", "'")
        .gsub("&lt;", "<")
        .gsub("&gt;", ">")
    end

    private def add_param(params : Array(Param), name : String, param_type : String)
      return if params.any? { |param| param.name == name && param.param_type == param_type }

      params << Param.new(name, "", param_type)
    end
  end
end
