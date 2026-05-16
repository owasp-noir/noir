require "../models/endpoint"
require "../models/logger"
require "../utils/*"

# Endpoint optimization module that handles endpoint deduplication,
# URL combination, and path parameter extraction
class EndpointOptimizer
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @pvalue_rules : Hash(String, Array(PValueRule))

  private struct PValueRule
    property key : String?
    property value : String

    def initialize(@key : String?, @value : String)
    end
  end

  def initialize(@logger : NoirLogger, @options : Hash(String, YAML::Any))
    @pvalue_rules = initialize_pvalue_rules
  end

  # Main optimization workflow - calls all optimization steps
  def optimize(endpoints : Array(Endpoint)) : Array(Endpoint)
    optimized = optimize_endpoints(endpoints)
    optimized = combine_url_and_endpoints(optimized)
    optimized = normalize_url_shapes(optimized)
    optimized = add_path_parameters(optimized)
    optimized
  end

  # Normalize cross-framework URL shapes the analyzers can't always
  # resolve without language context. Rewrites a small set of well-
  # known leaky forms into the canonical `{name}` placeholder so the
  # downstream `add_path_parameters` pass picks them up as path
  # params instead of literal noise.
  #
  # Covered shapes:
  #   - `(?P<name>pattern)` — Python `re_path`-style named groups.
  #     Bleeds through Django's `re_path` route table; rewrite to
  #     `{name}` and drop the regex body.
  #   - `${name}` / `${obj.field}` — JS/TS template literals that
  #     analyzers can't statically resolve (handler files reference
  #     captured variables, not literal paths). Rewrite to `{name}`
  #     (or `{field}` for `${obj.field}`) so the AI/output payload
  #     surfaces it as a path placeholder rather than as a literal
  #     `${...}` segment.
  #   - Python regex anchors `^` (leading) and `$`/`\Z` (trailing) —
  #     `re_path` patterns commonly include these.
  #   - Python regex backslash-escaped dots `\.` — rewrite to plain
  #     `.` for the visible URL.
  def normalize_url_shapes(endpoints : Array(Endpoint)) : Array(Endpoint)
    # `Endpoint` is a value-type struct in Crystal, so mutating
    # through the block-local binding only edits a copy. Rewrite
    # via array index so the in-place change actually persists.
    endpoints.each_with_index do |endpoint, idx|
      url = endpoint.url
      next if url.empty?

      # Skip URLs that look like a verbatim regex literal — Express
      # accepts `app.get(/^\/api\/(\d+)$/, handler)` and the route
      # extractor preserves the literal as the URL. Detect via
      # escaped slashes (`\/`) or regex character classes (`\d`/`\w`/
      # `\s`/`\D`/`\W`/`\S`/`(\d+)` etc.) the path forms never carry.
      next if url.includes?("\\/") || url.matches?(/\\[dswDSW]/)

      # Python `re_path` named groups: `(?P<name>...)` → `{name}`.
      # Use a hand-walked replacement so the inner regex body (which
      # can contain its own balanced parens / brackets) is consumed
      # correctly without writing a recursive regex.
      url = strip_python_named_groups(url)

      # JS/TS template-literal interpolations the parser couldn't
      # resolve. Pick the rightmost identifier token in the
      # expression — it's almost always the value-carrying name:
      #   `${id}`                 → `{id}`
      #   `${obj.field}`          → `{field}`
      #   `${get(id)}`            → `{id}`
      #   `${getThing().id}`      → `{id}`
      #   `${utils.fmt(value)}`   → `{value}`
      # Falls back to `{var}` when the expression has no extractable
      # identifier (e.g., `${1+2}` or `${"raw"}`).
      url = url.gsub(/\$\{([^{}]+)\}/) do |_match|
        expr = $1.to_s
        tokens = expr.split(/[^A-Za-z0-9_]/).reject(&.empty?)
        name = tokens.last? || ""
        name.empty? ? "{var}" : "{#{name}}"
      end

      # Strip Python regex anchors at the path boundary.
      url = url.sub(/^\/\^/, "/")
      url = url.sub(/\$$/, "")
      url = url.sub(/\\Z$/, "")
      url = url.sub(/\/\$$/, "/")

      # Backslash-escaped dots (re_path `r"\.json"`) → literal dot.
      url = url.gsub("\\.", ".")

      # Final double-slash collapse in case the rewrites left an
      # adjacent pair (e.g., trimming a leading `^` after `/`).
      # Skip when the URL carries a scheme like `https://` — the
      # HAR / OAS detectors emit absolute URLs and the `//` after
      # the colon is structural, not a path separator.
      unless url.matches?(/\A[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//)
        url = url.gsub_repeatedly("//", "/")
      end

      endpoint.url = url
      endpoints[idx] = endpoint
    end

    endpoints
  end

  # Rewrites every `(?P<name>...)` occurrence in `url` to `{name}`,
  # consuming the matching `)` even when the inner pattern contains
  # nested parens. Returns `url` unchanged when no named group is
  # present.
  private def strip_python_named_groups(url : String) : String
    return url unless url.includes?("(?P<")

    result = String::Builder.new
    i = 0
    size = url.size
    while i < size
      if i + 3 < size && url[i] == '(' && url[i + 1] == '?' && url[i + 2] == 'P' && url[i + 3] == '<'
        close_name = url.index('>', i + 4)
        unless close_name
          result << url[i..]
          break
        end
        name = url[(i + 4)...close_name]

        # Walk to the matching `)` from after the name's `>`.
        depth = 1
        j = close_name + 1
        while j < size && depth > 0
          ch = url[j]
          case ch
          when '\\'
            j += 2
            next
          when '['
            close_bracket = url.index(']', j + 1) || size
            j = close_bracket + 1
            next
          when '('
            depth += 1
          when ')'
            depth -= 1
          end
          j += 1
        end

        result << "{#{name}}"
        i = j
      else
        result << url[i]
        i += 1
      end
    end

    result.to_s
  end

  # Remove duplicated endpoints and parameters, validate HTTP methods, clean URLs
  def optimize_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.info "Optimizing endpoints."
    @logger.sub "➔ Removing duplicated endpoints and params."
    final_map = {} of Tuple(String, String) => Endpoint
    duplicate_count = 0
    allowed_methods = get_allowed_methods

    endpoints.each do |endpoint|
      tiny_tmp = endpoint

      # Check if method is allowed, otherwise default to GET
      if !allowed_methods.includes?(tiny_tmp.method.upcase)
        @logger.debug_sub "  - Invalid HTTP method: '#{tiny_tmp.method}' for '#{tiny_tmp.url}', defaulting to GET"
        tiny_tmp.method = "GET"
      end

      # Remove space in param name
      if endpoint.params.present?
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            param.value = apply_pvalue(param.param_type, param.name, param.value).to_s
            tiny_tmp.params << param
          end
        end
      end

      # Duplicate check
      if tiny_tmp.url != ""
        # Check start with slash
        if tiny_tmp.url[0] != "/"
          tiny_tmp.url = "/#{tiny_tmp.url}"
        end

        # Check double slash
        tiny_tmp.url = tiny_tmp.url.gsub_repeatedly("//", "/")

        key = {tiny_tmp.method, tiny_tmp.url}

        if final_map.has_key?(key)
          dup = final_map[key]
          @logger.debug_sub "  - Found duplicated endpoint: #{tiny_tmp.method} #{tiny_tmp.url}"
          duplicate_count += 1
          tiny_tmp.params.each do |param|
            existing_param = dup.params.find { |dup_param| dup_param.name == param.name }
            unless existing_param
              dup.params << param
            end
          end
        else
          final_map[key] = tiny_tmp
        end
      end
    end

    @logger.verbose_sub "➔ Total duplicated endpoints: #{duplicate_count}"
    final_map.values
  end

  # Combine target URL with endpoints
  def combine_url_and_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    tmp = [] of Endpoint
    target_url = @options["url"].to_s

    if target_url != ""
      @logger.sub "➔ Combining url and endpoints."
      @logger.debug_sub " + Before size: #{endpoints.size}"

      endpoints.each do |endpoint|
        tmp_endpoint = endpoint
        if tmp_endpoint.url.includes? target_url
          tmp_endpoint.url = tmp_endpoint.url.gsub(target_url, "")
        end

        tmp_endpoint.url = tmp_endpoint.url.gsub_repeatedly("//", "/")
        if tmp_endpoint.url != ""
          if target_url[-1] == '/' && tmp_endpoint.url[0] == '/'
            tmp_endpoint.url = tmp_endpoint.url[1..]
          elsif target_url[-1] != '/' && tmp_endpoint.url[0] != '/'
            tmp_endpoint.url = "/#{tmp_endpoint.url}"
          end
        end

        tmp_endpoint.url = target_url + tmp_endpoint.url
        tmp << tmp_endpoint
      end

      @logger.debug_sub " + After size: #{tmp.size}"
      tmp
    else
      endpoints
    end
  end

  # Add path parameters by parsing URL patterns
  def add_path_parameters(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.sub "➔ Adding path parameters by URL."
    final = [] of Endpoint

    endpoints.each do |endpoint|
      new_endpoint = endpoint

      # Handle {param} patterns
      scans = endpoint.url.scan(/\/\{([^}]+)\}/).flatten
      scans.each do |match|
        param = match[1].split(":")[0]
        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("{#{match[1]}}", new_value)
        end

        new_param = Param.new(param, "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      # Handle /:param patterns
      scans = endpoint.url.scan(/\/:([^\/]+)/).flatten
      scans.each do |match|
        new_value = apply_pvalue("path", match[1], "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub(":#{match[1]}", new_value)
        end

        new_param = Param.new(match[1], "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      # Handle <param> patterns (Django/Marten style)
      scans = endpoint.url.scan(/<([^>]+)>/).flatten
      scans.each do |match|
        parts = match[1].split(":")
        if parts.size > 1
          # Handle both Django style <type:name> and Marten style <name:type>
          # Check if first part looks like a type (int, str, slug, uuid, etc.)
          if parts[0] =~ /^(int|str|string|slug|uuid|float|bool|path)$/
            # Django style: <type:name>
            param = parts[1]
          else
            # Marten style: <name:type>
            param = parts[0]
          end
        else
          param = parts[0]
        end

        new_value = apply_pvalue("path", param, "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("<#{match[1]}>", new_value)
        end

        new_param = Param.new(param, "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      # Handle /*param patterns (wildcard/glob parameters)
      scans = endpoint.url.scan(/\/\*([^\/]+)/).flatten
      scans.each do |match|
        new_value = apply_pvalue("path", match[1], "")
        if new_value != ""
          new_endpoint.url = new_endpoint.url.gsub("*#{match[1]}", new_value)
        end

        new_param = Param.new(match[1], "", "path")
        unless new_endpoint.params.includes?(new_param)
          new_endpoint.params << new_param
        end
      end

      final << new_endpoint
    end

    final
  end

  # Apply parameter values based on configuration
  def apply_pvalue(param_type, param_name, param_value) : String
    if rules = @pvalue_rules[param_type]?
      rules.each do |rule|
        if rule.key.nil? || rule.key == param_name
          return rule.value
        end
      end
    end

    param_value.to_s
  end

  private def initialize_pvalue_rules : Hash(String, Array(PValueRule))
    rules = Hash(String, Array(PValueRule)).new
    param_types = ["query", "json", "form", "header", "cookie", "path"]
    global_pvalue = @options["set_pvalue"].as_a

    param_types.each do |type|
      pvalue_target = case type
                      when "query"  then @options["set_pvalue_query"]
                      when "json"   then @options["set_pvalue_json"]
                      when "form"   then @options["set_pvalue_form"]
                      when "header" then @options["set_pvalue_header"]
                      when "cookie" then @options["set_pvalue_cookie"]
                      when "path"   then @options["set_pvalue_path"]
                      else               YAML::Any.new([] of YAML::Any)
                      end

      merged_pvalue_target = [] of YAML::Any
      merged_pvalue_target.concat(pvalue_target.as_a)
      merged_pvalue_target.concat(global_pvalue)

      rules[type] = parse_rules(merged_pvalue_target)
    end

    rules
  end

  private def parse_rules(yaml_rules : Array(YAML::Any)) : Array(PValueRule)
    parsed_rules = [] of PValueRule
    yaml_rules.each do |pvalue|
      pvalue_str = pvalue.to_s
      key = nil
      value = pvalue_str

      if pvalue_str.includes?("=") || pvalue_str.includes?(":")
        first_equal = pvalue_str.index("=")
        first_colon = pvalue_str.index(":")

        if first_equal && (!first_colon || first_equal < first_colon)
          split = pvalue_str.split("=", 2)
          key = split[0]
          value = split[1]
        elsif first_colon
          split = pvalue_str.split(":", 2)
          key = split[0]
          value = split[1]
        end
      end

      if key == "*"
        key = nil
      end

      parsed_rules << PValueRule.new(key, value)
    end
    parsed_rules
  end

  # Get allowed HTTP methods
  private def get_allowed_methods : Array(String)
    ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT", "ANY"]
  end
end
