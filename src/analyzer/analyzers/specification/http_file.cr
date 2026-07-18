require "../../../models/analyzer"
require "../../../utils/http_symbols"
require "uri"

module Analyzer::Specification
  # Parses `.http` / `.rest` request files — the format shared by the VS Code
  # REST Client extension and the JetBrains HTTP Client.
  #
  # Requests are separated by `###`; the text after `###` is a name/comment.
  # A request is `METHOD url [HTTP/version]` (the method is optional and
  # defaults to `GET`), followed by header lines, a blank line, and an
  # optional body. `{{var}}` placeholders resolve from in-file `@name = value`
  # definitions; anything left unresolved in the path is treated as a path
  # parameter (`:var`) rather than literal text. JetBrains response-handler
  # blocks (`> {% ... %}` / `> script.js`) are skipped.
  class HttpFile < Analyzer
    HTTP_METHODS = ALLOWED_HTTP_METHODS

    def analyze
      locator = CodeLocator.instance
      http_files = locator.all("http-file")

      http_files.each do |http_file|
        next unless File.exists?(http_file)
        begin
          content = read_file_content(http_file)
          process_file(content, http_file)
        rescue e
          @logger.debug "Exception processing #{http_file}"
          @logger.debug_sub e
        end
      end

      @result
    end

    # A single `###`-delimited request within a file, kept with the 1-based
    # line number of its first line for endpoint source locations.
    private record Block, lines : Array(String), start_line : Int32

    private def process_file(content : String, source_path : String)
      env = collect_variables(content)
      split_blocks(content).each do |block|
        begin
          process_block(block, env, source_path)
        rescue e
          @logger.debug "Exception processing .http request block"
          @logger.debug_sub e
        end
      end
    end

    # File-scoped `@name = value` variable definitions. Collected in a single
    # pre-pass so a request can reference a variable defined anywhere in the
    # file. Only lines whose stripped form starts with `@` are considered, so
    # JSON/form body lines can't be mistaken for definitions.
    private def collect_variables(content : String) : Hash(String, String)
      env = {} of String => String
      content.each_line do |line|
        stripped = line.strip
        next unless stripped.starts_with?('@')
        if m = stripped.match(/^@([A-Za-z0-9_\-]+)\s*=\s*(.*)$/)
          env[m[1]] = m[2].strip
        end
      end
      env
    end

    private def split_blocks(content : String) : Array(Block)
      blocks = [] of Block
      current = [] of String
      start_line = 1
      line_no = 0

      content.each_line do |line|
        line_no += 1
        # A line beginning with `###` separates requests; the trailing text is
        # a comment/name and must not leak into the endpoint.
        if line.lstrip.starts_with?("###")
          blocks << Block.new(current, start_line) unless current.empty?
          current = [] of String
          start_line = line_no + 1
          next
        end
        current << line
      end
      blocks << Block.new(current, start_line) unless current.empty?
      blocks
    end

    private def process_block(block : Block, env : Hash(String, String), source_path : String)
      lines = block.lines
      idx = 0
      size = lines.size

      # Skip leading comments, blank lines and `@var` definitions.
      while idx < size
        stripped = lines[idx].strip
        if stripped.empty? || comment?(stripped) || stripped.starts_with?('@')
          idx += 1
        else
          break
        end
      end
      return if idx >= size

      request_line_offset = idx
      method, url_raw = parse_request_line(lines[idx].strip, env)
      return if method.nil? || url_raw.nil?
      idx += 1

      params = [] of Param

      # Headers run until the first blank line.
      while idx < size
        line = lines[idx]
        stripped = line.strip
        idx += 1
        break if stripped.empty?
        next if comment?(stripped)
        if sep = stripped.index(':')
          name = stripped[0...sep].strip
          value = stripped[(sep + 1)..].strip
          next if name.empty?
          next if skipped_header?(name)
          add_param(params, name, resolve_vars(value, env), "header")
        end
      end

      # Everything after the blank line is the body, up to a response-handler
      # line (`>`), which must not be treated as body content.
      body_lines = [] of String
      while idx < size
        stripped = lines[idx].strip
        break if stripped.starts_with?('>')
        body_lines << lines[idx]
        idx += 1
      end
      extract_body_params(body_lines.join('\n'), env).each { |p| params << p }

      url_path = extract_path_from_url(url_raw)
      return if url_path.empty?

      extract_query_param_names(url_raw).each do |query_name|
        add_param(params, query_name, "", "query")
      end

      extract_path_vars(url_path).each do |path_name|
        add_param(params, path_name, "", "path")
      end

      details = Details.new(PathInfo.new(source_path, block.start_line + request_line_offset))
      @result << Endpoint.new(url_path, method, params, details)
    end

    private def comment?(stripped : String) : Bool
      stripped.starts_with?('#') || stripped.starts_with?("//")
    end

    # Returns `{method, resolved_url}` for a request line, or `{nil, nil}` when
    # the line is not a request. The line is `METHOD url [HTTP/version]`; the
    # method is optional (defaults to GET) but a method-less line must still
    # look like a URL/path so header-shaped lines aren't misread as requests.
    private def parse_request_line(line : String, env : Hash(String, String)) : Tuple(String?, String?)
      parts = line.split(/[ \t]+/)
      return {nil, nil} if parts.empty?

      first = parts[0].upcase
      if HTTP_METHODS.includes?(first)
        return {nil, nil} if parts.size < 2
        target = parts[1]
        # An explicit method is not enough — the target must be URL-ish, so a
        # prose line like "Get started with the API" isn't read as a request.
        return {nil, nil} unless target_like?(target)
        {first, resolve_vars(target, env)}
      else
        target = parts[0]
        return {nil, nil} unless looks_like_target?(target)
        {"GET", resolve_vars(target, env)}
      end
    end

    # A request target always carries a URL-ish char (`.` `/` `:` `{`);
    # prose words never do.
    private def target_like?(value : String) : Bool
      value.matches?(/[.\/:{]/)
    end

    private def looks_like_target?(value : String) : Bool
      value.matches?(/^https?:\/\//i) || value.starts_with?('/') || value.starts_with?("{{")
    end

    private def extract_body_params(body : String, env : Hash(String, String)) : Array(Param)
      params = [] of Param
      stripped = body.strip
      return params if stripped.empty?

      # Prefer a JSON object body; fall back to `application/x-www-form-
      # urlencoded`. A templated body (`{ "id": {{x}} }`) is invalid JSON and
      # has no `=` pairs, so it is skipped silently — same as Bruno.
      begin
        parsed = JSON.parse(stripped)
        if hash = parsed.as_h?
          hash.each { |k, v| add_param(params, k, v.to_s, "json") }
          return params
        end
      rescue
        # Not JSON — try form encoding below.
      end

      if stripped.includes?('=') && !stripped.includes?('{')
        stripped.split('&').each do |pair|
          next if pair.empty?
          idx = pair.index('=')
          next if idx.nil?
          name = pair[0...idx].strip
          value = pair[(idx + 1)..].strip
          add_param(params, name, resolve_vars(value, env), "form")
        end
      end

      params
    end

    # ------ shared helpers (mirrors the Insomnia analyzer) ------

    # Substitutes `{{ var }}` / `{{var}}` tokens using the collected
    # variables. Unknown tokens are left as-is so the URL parser can turn
    # them into path parameters.
    private def resolve_vars(input : String, env : Hash(String, String)) : String
      return input if input.empty? || env.empty? || !input.includes?("{{")
      resolved = input
      3.times do
        previous = resolved
        resolved = resolved.gsub(/\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/) do |match|
          env.fetch($1, match)
        end
        break if resolved == previous
      end
      resolved
    end

    private def extract_path_from_url(url_string : String) : String
      stripped = url_string.strip
      return "" if stripped.empty?

      if stripped =~ /^https?:\/\//i
        begin
          uri = URI.parse(stripped)
          path = uri.path
          return normalize_path(path.empty? ? "/" : path)
        rescue e
          logger.debug "Failed to parse .http URL '#{stripped}': #{e}"
        end
      elsif stripped =~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//
        return ""
      end

      # No scheme — treat as path-only or host-prefixed.
      without_query = stripped.split("?", 2)[0].split("#", 2)[0]
      path = without_query
      unless path.starts_with?("/")
        if looks_host_prefixed?(path)
          parts = path.split("/", 2)
          return "/" if parts.size == 1
          path = "/" + parts[1]
        else
          path = "/" + path
        end
      end
      normalize_path(path)
    end

    private def extract_query_param_names(url_string : String) : Array(String)
      query = ""
      begin
        uri = URI.parse(url_string)
        query = uri.query || ""
      rescue e
        logger.debug "Failed to parse .http query URL '#{url_string}': #{e}"
      end

      if query.empty?
        idx = url_string.index('?')
        if idx
          query = url_string[(idx + 1)..].split("#", 2)[0]
        end
      end

      names = [] of String
      query.split('&').each do |pair|
        next if pair.empty?
        name = pair.split('=', 2).first.strip
        names << name unless name.empty?
      end
      names
    end

    private def extract_path_vars(path : String) : Array(String)
      vars = [] of String
      path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) { |m| vars << m[1] }
      path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)\}/) { |m| vars << m[1] }
      vars
    end

    private def looks_host_prefixed?(value : String) : Bool
      first = value.split("/", 2).first
      first.includes?(".") || first.includes?(":") || first.downcase == "localhost" || first.includes?("{{")
    end

    private def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized.gsub(/\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/) do
        ":#{normalize_var_name($1)}"
      end
    end

    private def normalize_var_name(name : String) : String
      normalized = name.gsub(/[^A-Za-z0-9_]/, "_")
      normalized = normalized.lstrip('_').rstrip('_')
      normalized.empty? ? "param" : normalized
    end

    private def add_param(params : Array(Param), name : String, value : String, param_type : String)
      normalized = name.strip
      return if normalized.empty?
      return if params.any? { |p| p.name == normalized && p.param_type == param_type }
      params << Param.new(normalized, value, param_type)
    end

    private def skipped_header?(name : String) : Bool
      normalized = name.strip.downcase
      normalized.empty? || normalized == "content-type" || normalized == "content-length" || normalized == "host"
    end
  end
end
