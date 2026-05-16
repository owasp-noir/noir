require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"

module Analyzer::Javascript
  class Nextjs < JavascriptEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    EXTENSIONS   = [".js", ".jsx", ".ts", ".tsx", ".mjs"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan(EXTENSIONS) do |path|
        if app_router_file?(path)
          analyze_app_router_file(path, result, mutex, include_callee)
        elsif pages_router_file?(path)
          analyze_pages_router_file(path, result, mutex, include_callee)
        else
          analyze_server_actions_file(path, result, mutex, include_callee)
        end
      end

      result
    end

    private def app_router_file?(path : String) : Bool
      return false unless path.includes?("/app/")
      EXTENSIONS.any? { |ext| path.ends_with?("/route#{ext}") }
    end

    private def pages_router_file?(path : String) : Bool
      path.includes?("/pages/api/")
    end

    private def analyze_pages_router_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      idx = path.index("/pages/api/")
      return if idx.nil?

      relative = path[(idx + "/pages/api/".size)..-1]
      relative = strip_extension(relative)

      # Skip private folders/files (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      url = "/api/" + convert_segments(relative)
      url = normalize_url(url)

      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      methods = detect_pages_router_methods(content)
      default_body_info = include_callee ? extract_default_export_body(content) : nil

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(path, 1))

        extract_path_params(url, endpoint)
        extract_pages_router_params(content, endpoint)
        if include_callee
          body_info = extract_exported_method_body(content, method) || default_body_info
          attach_callees(endpoint, path, body_info) if body_info
        end

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_app_router_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      idx = path.index("/app/")
      return if idx.nil?

      relative = path[(idx + "/app/".size)..-1]
      # Drop /route.ext
      EXTENSIONS.each do |ext|
        if relative.ends_with?("/route#{ext}")
          relative = relative[0..(relative.size - "/route#{ext}".size - 1)]
          break
        elsif relative == "route#{ext}"
          relative = ""
          break
        end
      end

      # Skip private folders (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      # Strip route groups (parenthesized segments)
      segments = relative.split("/").reject { |seg| seg.empty? || (seg.starts_with?("(") && seg.ends_with?(")")) }
      converted = segments.map { |seg| convert_segment(seg) }

      url = "/" + converted.join("/")
      url = normalize_url(url)

      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      methods = extract_app_router_methods(content)
      return if methods.empty?

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(path, 1))

        extract_path_params(url, endpoint)
        extract_app_router_params(content, endpoint)
        if include_callee
          body_info = extract_exported_method_body(content, method)
          attach_callees(endpoint, path, body_info) if body_info
        end

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_server_actions_file(path : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      # File must declare "use server" directive at the top
      return unless has_use_server_directive?(content)

      seen = Set(String).new

      # export async function NAME(args) { ... }
      content.scan(/export\s+async\s+function\s+(\w+)\s*\(([^)]*)\)/) do |match|
        action_name = match[1]
        next if seen.includes?(action_name)
        seen << action_name
        register_server_action(path, action_name, match[2], content, match, result, mutex, include_callee)
      end

      # export const NAME = async (args) => { ... }
      content.scan(/export\s+const\s+(\w+)\s*=\s*async\s*\(([^)]*)\)/) do |match|
        action_name = match[1]
        next if seen.includes?(action_name)
        seen << action_name
        register_server_action(path, action_name, match[2], content, match, result, mutex, include_callee)
      end

      # Note: `export default` actions are unaddressable by name, and
      # `export { foo, bar }` re-exports are out of scope (too complex to parse safely).
    end

    private def register_server_action(path : String, action_name : String, args : String,
                                       content : String, match : Regex::MatchData,
                                       result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      body_info = extract_action_body(content, match)
      body = body_info.try(&.[0]) || ""

      url = "/" + action_name
      endpoint = Endpoint.new(url, "POST")
      endpoint.details = Details.new(PathInfo.new(path, 1))

      extract_server_action_params(args, body, endpoint)
      attach_callees(endpoint, path, body_info) if include_callee && body_info

      mutex.synchronize { result << endpoint }
    end

    # Return the text and opening line for the braced function body that starts
    # after the match's args list.
    private def extract_action_body(content : String, match : Regex::MatchData) : Tuple(String, Int32)?
      match_end = match.end(0)
      return if match_end.nil?
      extract_braced_body(content, match_end)
    end

    private def extract_default_export_body(content : String) : Tuple(String, Int32)?
      match = content.match(/export\s+default\s+(?:async\s+)?function(?:\s+\w+)?\s*\([^)]*\)/)
      if match
        match_end = match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      arrow_match = content.match(/export\s+default\s+(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/)
      if arrow_match
        match_end = arrow_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      alias_match = content.match(/export\s+default\s+([A-Za-z_$][\w$]*)\s*;?/)
      extract_named_function_body(content, alias_match[1]) if alias_match
    end

    private def extract_exported_method_body(content : String, method : String) : Tuple(String, Int32)?
      if body_info = extract_direct_exported_method_body(content, method)
        return body_info
      end

      if local_name = exported_alias_for_method(content, method)
        extract_named_function_body(content, local_name)
      end
    end

    private def extract_direct_exported_method_body(content : String, method : String) : Tuple(String, Int32)?
      escaped_method = Regex.escape(method)
      function_match = content.match(/export\s+(?:async\s+)?function\s+#{escaped_method}\b\s*\([^)]*\)/)
      if function_match
        match_end = function_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      const_match = content.match(/export\s+const\s+#{escaped_method}\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/)
      if const_match
        match_end = const_match.end(0)
        extract_braced_body(content, match_end) if match_end
      end
    end

    private def extract_named_function_body(content : String, name : String) : Tuple(String, Int32)?
      escaped_name = Regex.escape(name)
      function_match = content.match(/(?:^|[^\w$])(?:async\s+)?function\s+#{escaped_name}\b\s*\([^)]*\)/)
      if function_match
        match_end = function_match.end(0)
        return extract_braced_body(content, match_end) if match_end
      end

      const_match = content.match(/(?:const|let|var)\s+#{escaped_name}\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)(?:\s*:\s*[^=]+?)?\s*=>/)
      if const_match
        match_end = const_match.end(0)
        extract_braced_body(content, match_end) if match_end
      end
    end

    private def exported_alias_for_method(content : String, method : String) : String?
      content.scan(/export\s+\{([^}]+)\}/) do |match|
        split_top_level_commas(match[1]).each do |part|
          pieces = part.strip.split(/\s+as\s+/)
          next if pieces.empty?

          if pieces.size == 1
            name = pieces[0].strip
            return name if name == method
          elsif pieces.size == 2
            local_name = pieces[0].strip
            exported_name = pieces[1].strip
            return local_name if exported_name == method
          end
        end
      end
    end

    private def extract_braced_body(content : String, start_pos : Int32) : Tuple(String, Int32)?
      open_pos = content.index('{', start_pos)
      return if open_pos.nil?
      depth = 1
      i = open_pos + 1
      while i < content.size && depth > 0
        case content[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          break if depth == 0
        end
        i += 1
      end
      return if depth > 0

      {content[(open_pos + 1)...i], line_for_index(content, open_pos)}
    end

    private def attach_callees(endpoint : Endpoint, path : String, body_info : Tuple(String, Int32))
      body, open_brace_line = body_info
      language = typescript_source?(path) ? :typescript : :javascript
      Noir::JSCalleeExtractor.callees_for_function_body(body, path, open_brace_line, language: language).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def typescript_source?(path : String) : Bool
      path.ends_with?(".ts") || path.ends_with?(".tsx")
    end

    private def line_for_index(content : String, index : Int32) : Int32
      content.to_slice[0, index].count('\n'.ord.to_u8) + 1
    end

    private def detect_pages_router_methods(content : String) : Array(String)
      # If named HTTP method exports exist, use them; otherwise default handler covers all.
      explicit = [] of String
      HTTP_METHODS.each do |m|
        if content.match(/export\s+(?:async\s+)?function\s+#{m}\b/) ||
           content.match(/export\s+const\s+#{m}\s*=/)
          explicit << m
        end
      end

      return explicit unless explicit.empty?

      # Heuristic: look for req.method checks to infer declared methods.
      inferred = [] of String
      content.scan(/req\.method\s*===?\s*['"]([A-Z]+)['"]/) do |m|
        method = m[1]
        inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
      end

      return inferred unless inferred.empty?

      # Default-export handler — applies to ALL methods.
      ["GET", "POST", "PUT", "DELETE", "PATCH"]
    end

    private def extract_app_router_methods(content : String) : Array(String)
      methods = [] of String
      HTTP_METHODS.each do |m|
        if content.match(/export\s+(?:async\s+)?function\s+#{m}\b/) ||
           content.match(/export\s+const\s+#{m}\s*=/) ||
           content.match(/export\s+\{[^}]*\b#{m}\b[^}]*\}/)
          methods << m
        end
      end
      methods
    end

    private def extract_pages_router_params(content : String, endpoint : Endpoint)
      # req.query.X and req.query["X"]
      content.scan(/req\.query\.(\w+)/) do |m|
        add_param(endpoint, m[1], "query")
      end
      content.scan(/req\.query\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # Destructured query: const { foo, bar } = req.query
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.query/) do |m|
        extract_simple_destructure_params(m[1]).each do |name|
          add_param(endpoint, name, "query")
        end
      end

      # req.body.X and req.body["X"]
      content.scan(/req\.body\.(\w+)/) do |m|
        add_param(endpoint, m[1], "body")
      end
      content.scan(/req\.body\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "body")
      end

      # Destructured body: const { foo, bar } = req.body
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.body/) do |m|
        extract_simple_destructure_params(m[1]).each do |name|
          add_param(endpoint, name, "body")
        end
      end

      # req.headers["x-token"] or req.headers.foo
      content.scan(/req\.headers\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "header")
      end
      content.scan(/req\.headers\.(\w+)/) do |m|
        add_param(endpoint, m[1], "header")
      end

      # req.cookies["session"] or req.cookies.name
      content.scan(/req\.cookies\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
      content.scan(/req\.cookies\.(\w+)/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
    end

    private def extract_app_router_params(content : String, endpoint : Endpoint)
      # request.nextUrl.searchParams.get("X") or searchParams.get("X")
      content.scan(/(?:searchParams|nextUrl\.searchParams)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # await request.json() — body present; try to extract field access patterns
      if content.includes?("request.json()") || content.includes?(".json()")
        # Destructured: const { foo, bar } = await request.json()
        content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*await\s+(?:request|req)\.json\s*\(\s*\)/) do |m|
          extract_simple_destructure_params(m[1]).each do |name|
            add_param(endpoint, name, "json")
          end
        end

        # Aliased: const body = await request.json(); then body.X or body["X"]
        content.scan(/(?:const|let|var)\s+(\w+)\s*=\s*await\s+(?:request|req)\.json\s*\(\s*\)/) do |m|
          varname = m[1]
          escaped = Regex.escape(varname)
          content.scan(/\b#{escaped}\.(\w+)/) do |mm|
            add_param(endpoint, mm[1], "json")
          end
          content.scan(/\b#{escaped}\[['"]([^'"]+)['"]\]/) do |mm|
            add_param(endpoint, mm[1], "json")
          end
        end
      end

      # formData: const formData = await request.formData(); formData.get("name")
      if content.includes?("formData()")
        content.scan(/formData\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
          add_param(endpoint, m[1], "form")
        end
      end

      # request.headers.get("x-token")
      content.scan(/(?:request|req)\.headers\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "header")
      end

      # cookies().get("session") from next/headers
      content.scan(/cookies\(\)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
    end

    private def extract_server_action_params(args : String, body : String, endpoint : Endpoint)
      # Scan the action body for .get("X") calls (formData.get / data.get, etc.) → form param
      body.scan(/\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "form")
      end

      # Extract only simple top-level identifier args (skip anything with {, <, =, ()
      split_top_level_commas(args).each do |arg|
        arg = arg.strip
        next if arg.empty?
        # Strip type annotation (everything after `:`)
        name_part = arg.split(":").first.strip
        # Skip destructures, generics, default values, nested calls
        next if name_part.includes?("{") || name_part.includes?("(") ||
                name_part.includes?("<") || name_part.includes?("=")
        next unless name_part.match(/^\w+$/)
        next if name_part == "formData"
        add_param(endpoint, name_part, "body")
      end
    end

    # Split a comma-separated string at top-level commas only (ignoring those inside
    # braces, brackets, parens, or angle brackets).
    private def split_top_level_commas(s : String) : Array(String)
      parts = [] of String
      depth = 0
      buffer = String::Builder.new
      s.each_char do |c|
        case c
        when '{', '[', '(', '<'
          depth += 1
          buffer << c
        when '}', ']', ')', '>'
          depth -= 1 if depth > 0
          buffer << c
        when ','
          if depth == 0
            parts << buffer.to_s
            buffer = String::Builder.new
          else
            buffer << c
          end
        else
          buffer << c
        end
      end
      parts << buffer.to_s
      parts
    end

    # Extract only simple top-level identifiers from a flat destructure body.
    # Returns [] if the destructure contains nested structures, type annotations,
    # or default values (too complex to parse safely).
    private def extract_simple_destructure_params(destructure : String) : Array(String)
      return [] of String if destructure.includes?("{") || destructure.includes?("(") ||
                             destructure.includes?("<") || destructure.includes?("=") ||
                             destructure.includes?(":")
      destructure.split(",").map(&.strip).select(&.match(/^\w+$/))
    end

    private def extract_path_params(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |m|
        add_param(endpoint, m[1], "path")
      end
    end

    private def add_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      return if endpoint.params.any? { |p| p.name == name && p.param_type == type }
      endpoint.push_param(Param.new(name, "", type))
    end

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_segments(relative : String) : String
      segments = relative.split("/").reject(&.empty?)
      segments.map { |seg| convert_segment(seg) }.join("/")
    end

    private def convert_segment(seg : String) : String
      # Optional catch-all: [[...slug]]
      if m = seg.match(/^\[\[\.\.\.(\w+)\]\]$/)
        return "{#{m[1]}}"
      end
      # Catch-all: [...slug]
      if m = seg.match(/^\[\.\.\.(\w+)\]$/)
        return "{#{m[1]}}"
      end
      # Dynamic: [id]
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def has_use_server_directive?(content : String) : Bool
      stripped = content.lstrip
      # Skip leading comments
      while stripped.starts_with?("//") || stripped.starts_with?("/*")
        if stripped.starts_with?("//")
          newline = stripped.index('\n')
          return false if newline.nil?
          stripped = stripped[(newline + 1)..].lstrip
        else
          close = stripped.index("*/")
          return false if close.nil?
          stripped = stripped[(close + 2)..].lstrip
        end
      end
      stripped.starts_with?(%("use server")) || stripped.starts_with?(%('use server'))
    end

    private def normalize_url(url : String) : String
      url = url.gsub(/\/+/, "/")
      url = url.sub(/\/index$/, "")
      url = url.sub(/\/+$/, "") unless url == "/"
      url = "/" if url.empty?
      url
    end
  end
end
