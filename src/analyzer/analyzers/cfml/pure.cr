require "../../engines/cfml_engine"

module Analyzer::Cfml
  # Plain CFML (ColdFusion / Lucee / BoxLang) attack surface.
  #
  # CFML has two directly-reachable shapes and no route table:
  #
  #   * `.cfm` pages are file-path routed — the path under the web root
  #     *is* the URL, exactly like plain PHP or JSP.
  #   * `.cfc` components are not reachable on their own, but any method
  #     declared `access="remote"` is callable over HTTP as
  #     `/path/To/Component.cfc?method=<name>`, with the declared
  #     arguments arriving as URL or FORM keys.
  #
  # Framework route tables (Taffy `taffy:uri`, ColdBox `Router.cfc`,
  # Wheels `config/routes.cfm`, FW/1 `variables.framework.routes`) are
  # deliberately out of scope here — they warrant their own techs so the
  # generic analyzer isn't the thing that decides framework semantics.
  class Pure < CfmlEngine
    # Only unambiguous web-root directory names. Bare `public/` and
    # `www/` were tried and dropped: they collide with build output such
    # as `docs/public/`, the same false positive `FileHelper` documents.
    #
    # Locating the root from `Application.cfc` was also tried and is
    # worse — every CFML sub-application, module and test harness ships
    # one (7-25 per repo across the validation corpus), so anchoring
    # collapsed Taffy's 20 example apps onto a single `/index.cfm`.
    # Leaving the path repo-relative keeps colliding pages distinct and
    # locatable.
    WEBROOT_MARKERS = ["webroot/", "wwwroot/", "htdocs/"]

    # Auto-run lifecycle includes, not requestable pages — the CFML
    # analogue of `global.asa`.
    LIFECYCLE_PAGES = Set{"application.cfm", "onrequestend.cfm"}

    # Script syntax has two spellings of the same thing. The prefix form
    # is matched loosely and its argument list is delimited by real paren
    # matching; the suffix form is driven off the `access` attribute so a
    # component with hundreds of private methods costs one scan, not one
    # paren walk per declaration.
    SCRIPT_REMOTE_PREFIX_RE = /(?<![\w.])remote\s+(?:\w+\s+)?function\s+(\w+)\s*\(/i
    SCRIPT_REMOTE_SUFFIX_RE = /(?<![\w.])function\s+(\w+)\s*\(([^)]*)\)([^{;]*?)access\s*=\s*["']remote["']/i
    SCRIPT_ACCESS_REMOTE_RE = /\baccess\s*=\s*["']remote["']/i

    # CFML is case-insensitive, so `access="ReMote"` is as valid as
    # `access="remote"`; gate on one case-insensitive pass rather than a
    # handful of literal spellings.
    REMOTE_HINT_RE = /remote/i

    # Request-scope reads on `.cfm` pages. The negative lookbehind keeps
    # `document.form.x` / `application.form.x` from registering as a
    # `form` scope read.
    SCOPE_PREFIX = "(?<![.\\w])(url|form|cookie)"

    CFPARAM_TAG_RE       = /<cfparam\b[^>]*?\bname\s*=\s*["'](url|form|cookie)\.(\w+)["']/i
    CFPARAM_SCRIPT_RE    = /(?<![.\w])param\b[^;\n]*?\bname\s*=\s*["'](url|form|cookie)\.(\w+)["']/i
    CFPARAM_ASSIGN_RE    = /(?<![.\w])param\s+(url|form|cookie)\.(\w+)\s*=/i
    SCOPE_DOT_RE         = /#{SCOPE_PREFIX}\.([A-Za-z_]\w*)/i
    SCOPE_BRACKET_RE     = /#{SCOPE_PREFIX}\s*\[\s*["']([^"'\]]+)["']\s*\]/i
    STRUCT_KEY_EXISTS_RE = /\bstructKeyExists\s*\(\s*(url|form|cookie)\s*,\s*["']([^"']+)["']\s*\)/i
    IS_DEFINED_RE        = /\bisDefined\s*\(\s*["'](url|form|cookie)\.(\w+)["']\s*\)/i

    SCOPE_PATTERNS = [CFPARAM_TAG_RE, CFPARAM_SCRIPT_RE, CFPARAM_ASSIGN_RE, SCOPE_DOT_RE,
                      SCOPE_BRACKET_RE, STRUCT_KEY_EXISTS_RE, IS_DEFINED_RE]

    # `cgi.http_x_forwarded_for` is the CFML spelling of an inbound
    # header. The other `cgi.*` keys (request_method, script_name, ...)
    # are server metadata, not request params.
    CGI_HEADER_RE = /(?<![.\w])cgi\.(http_[a-z_]+)/i

    # Client-side JavaScript routinely names a local `form`
    # (`form.submit()`, `form.action`), which the scope patterns above
    # would otherwise read as CFML form-scope access — inventing params
    # and flipping the page to POST. Script bodies are blanked, except
    # `#...#` spans, because CFML genuinely interpolates server values
    # into JS (`var id = #url.id#;`).
    SCRIPT_BLOCK_RE  = /(<script\b[^>]*>)([\s\S]*?)(<\/script>)/i
    INTERPOLATION_RE = /#[^#\n]+#/

    def analyze
      pages = cfml_pages.reject { |path| LIFECYCLE_PAGES.includes?(File.basename(path).downcase) }

      parallel_analyze(cfml_components) do |path|
        analyze_component(path)
      end

      parallel_analyze(pages) do |path|
        analyze_page(path)
      end

      @result
    end

    # `.cfc` — only `access="remote"` methods are reachable over HTTP.
    private def analyze_component(path : String)
      raw = read_file_content(path)
      return unless raw.matches?(REMOTE_HINT_RE)

      content = strip_cfml_comments(raw)
      base_url = web_root_path(path, WEBROOT_MARKERS)
      # A method may legally carry both spellings (`remote function x()
      # access="remote"`); emit it once.
      seen = Set(String).new

      extract_tag_remote_methods(content, path, base_url, seen)
      extract_script_remote_methods(content, path, base_url, seen)
    end

    private def extract_tag_remote_methods(content : String, path : String, base_url : String, seen : Set(String))
      return unless content.includes?("<cffunction") || content.includes?("<CFFUNCTION")

      content.scan(CFFUNCTION_TAG_RE) do |match|
        attrs = tag_attributes(match[1])
        next unless attrs["access"]?.try(&.downcase) == "remote"

        name = attrs["name"]?
        next if name.nil? || name.empty?

        tag_end = match.end(0)
        next unless tag_end

        params = tag_arguments(content, tag_end)
        emit_remote(path, base_url, name, params, line_number_for_index(content, match.begin(0) || 0), seen)
      end
    end

    private def extract_script_remote_methods(content : String, path : String, base_url : String, seen : Set(String))
      # `remote [type] function name(...)`
      content.scan(SCRIPT_REMOTE_PREFIX_RE) do |match|
        start = match.begin(0) || 0
        open_paren = content.index('(', start)
        next unless open_paren

        args = paren_content(content, open_paren)
        next unless args

        emit_remote(path, base_url, match[1], script_arguments(args), line_number_for_index(content, start), seen)
      end

      # `[type] function name(...) access="remote" {`
      return unless content.matches?(SCRIPT_ACCESS_REMOTE_RE)

      content.scan(SCRIPT_REMOTE_SUFFIX_RE) do |match|
        emit_remote(path, base_url, match[1], script_arguments(match[2]),
          line_number_for_index(content, match.begin(0) || 0), seen)
      end
    end

    # A remote method is reachable as GET and POST alike; the arguments
    # arrive in the URL or the form body accordingly.
    private def emit_remote(path : String, base_url : String, method_name : String,
                            arg_names : Array(String), line : Int32, seen : Set(String))
      return unless seen.add?(method_name.downcase)

      url = "#{base_url}?method=#{method_name}"
      details = Details.new(PathInfo.new(path, line))

      @result << Endpoint.new(url, "GET", arg_names.map { |name| Param.new(name, "", "query") }, details)
      @result << Endpoint.new(url, "POST", arg_names.map { |name| Param.new(name, "", "form") }, details)
    end

    # `.cfm` — the file itself is the route; request-scope reads are the params.
    private def analyze_page(path : String)
      content = mask_client_scripts(strip_cfml_comments(read_file_content(path)))
      url = web_root_path(path, WEBROOT_MARKERS)
      details = Details.new(PathInfo.new(path, 1))

      query = [] of Param
      body = [] of Param
      cookies = [] of Param
      headers = [] of Param

      SCOPE_PATTERNS.each do |pattern|
        content.scan(pattern) do |match|
          name = match[2]
          next if name.empty?

          case match[1].downcase
          when "url"    then query << Param.new(name, "", "query")
          when "form"   then body << Param.new(name, "", "form")
          when "cookie" then cookies << Param.new(name, "", "cookie")
          end
        end
      end

      content.scan(CGI_HEADER_RE) do |match|
        if header = http_header_name(match[1])
          headers << Param.new(header, "", "header")
        end
      end

      @result << Endpoint.new(url, "GET", unique_params(query + cookies + headers), details)

      return if body.empty?

      @result << Endpoint.new(url, "POST", unique_params(body + cookies + headers), details)
    end

    private def mask_client_scripts(content : String) : String
      return content unless content.includes?("<script") || content.includes?("<SCRIPT")

      content.gsub(SCRIPT_BLOCK_RE) do
        match = $~
        "#{match[1]}#{blank_outside_interpolations(match[2])}#{match[3]}"
      end
    end

    # Replace every character with a space, keeping newlines (so line
    # numbers hold) and `#...#` interpolations (so server-side reads
    # embedded in JS still register).
    private def blank_outside_interpolations(body : String) : String
      keep = Array(Bool).new(body.size, false)
      body.scan(INTERPOLATION_RE) do |match|
        start = match.begin(0)
        stop = match.end(0)
        next unless start && stop

        (start...stop).each { |index| keep[index] = true }
      end

      String.build do |io|
        body.each_char_with_index do |char, index|
          io << (char == '\n' || keep[index] ? char : ' ')
        end
      end
    end

    # TestBox names suites `<Something>Test.cfc` / `<Something>Spec.cfc`.
    # The leading `.+` is load-bearing: a component named exactly
    # `Test.cfc` is a demo, not a suite (fw1 ships one that declares a
    # real `remote` method), and an anchored `ends_with?` swallowed it.
    private def test_path?(path : String) : Bool
      return true if path.includes?("/tests/") || path.includes?("/test/")

      File.basename(path).matches?(TEST_COMPONENT_RE)
    end
  end
end
