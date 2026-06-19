require "../models/endpoint"
require "../miniparsers/js_route_extractor"

module Noir
  # Extracts routes from direct Node.js core http/https createServer handlers.
  #
  # This covers the stdlib shape where applications branch on req.method and
  # req.url/pathname inside a single request listener, rather than registering
  # routes through a framework DSL.
  class JSHttpRouteExtractor
    HTTP_METHODS = Set{
      "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE",
    }

    SOURCE_EXTENSIONS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".tsx"]

    struct Handler
      getter request_name : String
      getter body : String
      getter body_start_pos : Int32

      def initialize(@request_name : String, @body : String, @body_start_pos : Int32)
      end
    end

    struct Region
      getter values : Array(String)
      getter start_pos : Int32
      getter end_pos : Int32

      def initialize(@values : Array(String), @start_pos : Int32, @end_pos : Int32)
      end
    end

    struct ValueHit
      getter values : Array(String)
      getter offset : Int32
      getter scope_start_pos : Int32?
      getter scope_end_pos : Int32?

      def initialize(@values : Array(String), @offset : Int32, @scope_start_pos : Int32? = nil, @scope_end_pos : Int32? = nil)
      end
    end

    struct RouteHit
      getter method : String
      getter path : String
      getter offset : Int32
      getter scope_start_pos : Int32?
      getter scope_end_pos : Int32?

      def initialize(@method : String, @path : String, @offset : Int32, @scope_start_pos : Int32? = nil, @scope_end_pos : Int32? = nil)
      end
    end

    struct RequestRefs
      getter method_refs : Array(String)
      getter path_refs : Array(String)

      def initialize(@method_refs : Array(String), @path_refs : Array(String))
      end
    end

    def self.extract(file_path : String, content : String, debug : Bool = false) : Array(Endpoint)
      return [] of Endpoint unless source_file?(file_path)
      return [] of Endpoint unless content.includes?("createServer")

      stripped = JSRouteExtractor.strip_js_comments(content)
      if JSRouteExtractor.minified_content?(stripped)
        STDERR.puts "Skipping #{file_path} for node:http route extraction (minified/bundled asset)" if debug
        return [] of Endpoint
      end
      if JSRouteExtractor.test_stub_only?(file_path, stripped)
        STDERR.puts "Skipping #{file_path} for node:http route extraction (test-stub/non-server marker)" if debug
        return [] of Endpoint
      end

      named_handlers = collect_named_handlers(stripped)
      endpoints = [] of Endpoint
      seen = Set(Tuple(String, String)).new

      create_server_call_parens(stripped).each do |open_paren|
        close_paren = JSRouteExtractor.find_matching_paren(stripped, open_paren)
        next unless close_paren

        split_top_level_args(stripped, open_paren + 1, close_paren).each do |arg_source, arg_start|
          handler = handler_from_arg(stripped, arg_source, arg_start, named_handlers)
          next unless handler

          extract_route_hits(handler).each do |hit|
            key = {hit.method, hit.path}
            next if seen.includes?(key)
            seen << key

            line = line_for_pos(stripped, handler.body_start_pos + hit.offset)
            endpoint = Endpoint.new(hit.path, hit.method, Details.new(PathInfo.new(file_path, line)))
            push_path_params(endpoint)
            extract_params(handler, hit, endpoint)
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    def self.source_file?(file_path : String) : Bool
      SOURCE_EXTENSIONS.any? { |ext| file_path.ends_with?(ext) }
    end

    private def self.create_server_call_parens(content : String) : Array(Int32)
      starts = [] of Int32
      aliases = core_http_module_aliases(content)
      direct_names = direct_create_server_names(content)

      aliases.each do |name|
        content.scan(/\b#{Regex.escape(name)}\s*\.\s*createServer\s*\(/) do |match|
          match_start = match.begin(0) || 0
          if open_paren = content.index("(", match_start)
            starts << open_paren
          end
        end
      end

      direct_names.each do |name|
        content.scan(/(^|[^.\w$])#{Regex.escape(name)}\s*\(/) do |match|
          match_start = match.begin(0) || 0
          if open_paren = content.index("(", match_start)
            starts << open_paren
          end
        end
      end

      content.scan(/require\s*\(\s*['"](?:node:)?https?['"]\s*\)\s*\.\s*createServer\s*\(/) do |match|
        match_start = match.begin(0) || 0
        if open_paren = content.index("(", match_start)
          starts << open_paren
        end
      end

      starts.uniq
    end

    private def self.core_http_module_aliases(content : String) : Set(String)
      aliases = Set(String).new

      content.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*require\s*\(\s*['"](?:node:)?https?['"]\s*\)/) do |match|
        aliases.add(match[1]) if match.size > 1
      end

      content.scan(/import\s+(?:\*\s+as\s+)?([A-Za-z_$]\w*)\s+from\s+['"](?:node:)?https?['"]/) do |match|
        aliases.add(match[1]) if match.size > 1
      end

      content.scan(/import\s+([A-Za-z_$]\w*)\s*=\s*require\s*\(\s*['"](?:node:)?https?['"]\s*\)/) do |match|
        aliases.add(match[1]) if match.size > 1
      end

      aliases
    end

    private def self.direct_create_server_names(content : String) : Set(String)
      names = Set(String).new

      content.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*require\s*\(\s*['"](?:node:)?https?['"]\s*\)/) do |match|
        add_create_server_destructure_names(names, match[1]) if match.size > 1
      end

      content.scan(/import\s*\{\s*([^}]+)\s*\}\s*from\s*['"](?:node:)?https?['"]/) do |match|
        add_create_server_destructure_names(names, match[1]) if match.size > 1
      end

      names
    end

    private def self.add_create_server_destructure_names(names : Set(String), source : String) : Nil
      source.split(",").each do |raw_part|
        part = raw_part.strip
        if match = part.match(/^createServer\s+as\s+([A-Za-z_$]\w*)$/)
          names.add(match[1])
        elsif match = part.match(/^createServer\s*:\s*([A-Za-z_$]\w*)$/)
          names.add(match[1])
        elsif part == "createServer"
          names.add("createServer")
        end
      end
    end

    private def self.collect_named_handlers(content : String) : Hash(String, Handler)
      handlers = {} of String => Handler

      content.scan(/\bfunction\s+([A-Za-z_$]\w*)\s*\(/) do |match|
        name = match[1]
        start_pos = match.begin(0) || 0
        if handler = function_handler_at(content, start_pos)
          handlers[name] = handler
        end
      end

      content.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*(?::[^=;]+)?=\s*/) do |match|
        name = match[1]
        start_pos = (match.begin(0) || 0) + match[0].bytesize
        if handler = function_handler_at(content, start_pos)
          handlers[name] = handler
        elsif handler = arrow_handler_at(content, start_pos)
          handlers[name] = handler
        end
      end

      handlers
    end

    private def self.handler_from_arg(content : String,
                                      arg_source : String,
                                      arg_start : Int32,
                                      named_handlers : Hash(String, Handler)) : Handler?
      source = arg_source.strip
      if source.matches?(/^[A-Za-z_$]\w*$/)
        return named_handlers[source]?
      end

      if function_idx = source.index(/\bfunction\b/)
        return function_handler_at(content, arg_start + function_idx)
      end

      if source.includes?("=>")
        return arrow_handler_at(content, arg_start)
      end

      nil
    end

    private def self.function_handler_at(content : String, start_pos : Int32) : Handler?
      function_idx = content.index(/\bfunction\b/, start_pos)
      return unless function_idx
      return if function_idx - start_pos > 80

      param_open = content.index("(", function_idx)
      return unless param_open
      param_close = JSRouteExtractor.find_matching_paren(content, param_open)
      return unless param_close
      params = content[(param_open + 1)...param_close]
      request_name = first_param_name(params)
      return unless request_name

      open_brace = content.index("{", param_close)
      return unless open_brace
      close_brace = JSRouteExtractor.find_matching_brace(content, open_brace)
      return unless close_brace

      Handler.new(request_name, content[(open_brace + 1)...close_brace], open_brace + 1)
    end

    private def self.arrow_handler_at(content : String, start_pos : Int32) : Handler?
      arrow_idx = content.index("=>", start_pos)
      return unless arrow_idx
      return if arrow_idx - start_pos > 500

      params = arrow_params(content, start_pos, arrow_idx)
      request_name = first_param_name(params)
      return unless request_name

      body_start = skip_whitespace(content, arrow_idx + 2)
      return unless body_start < content.size && content[body_start] == '{'
      close_brace = JSRouteExtractor.find_matching_brace(content, body_start)
      return unless close_brace

      Handler.new(request_name, content[(body_start + 1)...close_brace], body_start + 1)
    end

    private def self.arrow_params(content : String, start_pos : Int32, arrow_idx : Int32) : String
      left_end = arrow_idx - 1
      while left_end >= start_pos && content[left_end].whitespace?
        left_end -= 1
      end

      if left_end >= start_pos && content[left_end] == ')'
        if left_open = find_open_paren_backward(content, left_end)
          return content[(left_open + 1)...left_end]
        end
      end

      left_start = left_end
      while left_start >= start_pos && identifier_char?(content[left_start])
        left_start -= 1
      end
      content[(left_start + 1)..left_end]
    end

    private def self.find_open_paren_backward(content : String, close_idx : Int32) : Int32?
      depth = 0
      i = close_idx
      while i >= 0
        case content[i]
        when ')'
          depth += 1
        when '('
          depth -= 1
          return i if depth == 0
        end
        i -= 1
      end
      nil
    end

    private def self.first_param_name(params : String) : String?
      raw = split_param_list(params).first?
      return unless raw

      param = raw.strip
      param = param.lchop("async").strip if param.starts_with?("async ")
      param = param.lchop("...").strip
      param = param.split("=", 2).first.strip
      param = param.split(":", 2).first.strip
      param = param.rchop("?") if param.ends_with?("?")
      return unless param.matches?(/^[A-Za-z_$]\w*$/)

      param
    end

    private def self.split_param_list(params : String) : Array(String)
      split_top_level(params, 0, params.size, ',').map(&.[0])
    end

    private def self.extract_route_hits(handler : Handler) : Array(RouteHit)
      refs = request_refs(handler.body, handler.request_name)
      routes = [] of RouteHit
      method_regions = [] of Region
      path_regions = [] of Region
      method_hits = [] of ValueHit
      path_hits = [] of ValueHit

      scan_if_conditions(handler.body) do |condition, offset, block_start, block_end|
        methods = extract_methods(condition, refs.method_refs)
        paths = extract_paths(condition, refs.path_refs)

        if !methods.empty? && !paths.empty?
          methods.each do |method|
            paths.each { |path| routes << RouteHit.new(method, path, offset, block_start, block_end) }
          end
        elsif !methods.empty?
          method_hits << ValueHit.new(methods, offset, block_start, block_end)
          if block_start && block_end
            method_regions << Region.new(methods, block_start, block_end)
          end
        elsif !paths.empty?
          path_hits << ValueHit.new(paths, offset, block_start, block_end)
          if block_start && block_end
            path_regions << Region.new(paths, block_start, block_end)
          end
        end
      end

      scan_switches(handler.body, refs.method_refs, refs.path_refs) do |kind, values, case_start, case_end|
        if kind == :method
          method_hits << ValueHit.new(values, case_start, case_start, case_end)
          method_regions << Region.new(values, case_start, case_end)
        else
          path_hits << ValueHit.new(values, case_start, case_start, case_end)
          path_regions << Region.new(values, case_start, case_end)
        end
      end

      path_hits.each do |hit|
        scoped_methods = values_for_offset(method_regions, hit.offset)
        if scoped_methods.empty?
          next if method_hit_inside_path_region?(path_regions, method_hits, hit)

          scoped_methods = ["GET"]
        end

        scoped_methods.each do |method|
          hit.values.each { |path| routes << RouteHit.new(method, path, hit.offset, hit.scope_start_pos, hit.scope_end_pos) }
        end
      end

      method_hits.each do |hit|
        scoped_paths = values_for_offset(path_regions, hit.offset)
        scoped_paths.each do |path|
          hit.values.each { |method| routes << RouteHit.new(method, path, hit.offset, hit.scope_start_pos, hit.scope_end_pos) }
        end
      end

      dedupe_route_hits(routes)
    end

    private def self.request_refs(body : String, request_name : String) : RequestRefs
      method_refs = ["#{request_name}.method"]
      path_refs = ["#{request_name}.url"]
      parsed_url_objects = Set(String).new

      req_ref = Regex.escape(request_name)

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*#{req_ref}\s*\.\s*method\b/) do |match|
        method_refs << match[1] if match.size > 1
      end

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*#{req_ref}\s*\.\s*url\b/) do |match|
        path_refs << match[1] if match.size > 1
      end

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*new\s+URL\s*\([^)]*#{req_ref}\s*\.\s*url[^)]*\)/) do |match|
        if match.size > 1
          parsed_url_objects.add(match[1])
          path_refs << "#{match[1]}.pathname"
        end
      end

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*(?:url|URL)\s*\.\s*parse\s*\([^)]*#{req_ref}\s*\.\s*url[^)]*\)/) do |match|
        if match.size > 1
          parsed_url_objects.add(match[1])
          path_refs << "#{match[1]}.pathname"
        end
      end

      parsed_url_objects.each do |object_name|
        body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*#{Regex.escape(object_name)}\s*\.\s*pathname\b/) do |match|
          path_refs << match[1] if match.size > 1
        end
      end

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*new\s+URL\s*\([^)]*#{req_ref}\s*\.\s*url[^)]*\)\s*\.\s*pathname\b/) do |match|
        path_refs << match[1] if match.size > 1
      end

      body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*#{req_ref}\b/) do |match|
        next unless match.size > 1
        match[1].split(",").each do |raw_part|
          source_name, local_name = destructured_pair(raw_part)
          case source_name
          when "method"
            method_refs << local_name
          when "url"
            path_refs << local_name
          end
        end
      end

      RequestRefs.new(method_refs.uniq, path_refs.uniq)
    end

    private def self.destructured_pair(raw_part : String) : Tuple(String, String)
      part = raw_part.strip
      part = part.split("=", 2).first.strip
      if part.includes?(":")
        pieces = part.split(":", 2).map(&.strip)
        {pieces[0], pieces[1]}
      else
        {part, part}
      end
    end

    private def self.scan_if_conditions(body : String, & : String, Int32, Int32?, Int32? -> Nil) : Nil
      body.scan(/\bif\s*\(/) do |match|
        if_start = match.begin(0) || 0
        open_paren = body.index("(", if_start)
        next unless open_paren
        close_paren = JSRouteExtractor.find_matching_paren(body, open_paren)
        next unless close_paren

        condition = body[(open_paren + 1)...close_paren]
        block_start = nil.as(Int32?)
        block_end = nil.as(Int32?)
        after_condition = skip_whitespace(body, close_paren + 1)
        if after_condition < body.size && body[after_condition] == '{'
          if close_brace = JSRouteExtractor.find_matching_brace(body, after_condition)
            block_start = after_condition + 1
            block_end = close_brace
          end
        end

        yield condition, if_start, block_start, block_end
      end
    end

    private def self.scan_switches(body : String,
                                   method_refs : Array(String),
                                   path_refs : Array(String),
                                   & : Symbol, Array(String), Int32, Int32 -> Nil) : Nil
      body.scan(/\bswitch\s*\(/) do |match|
        switch_start = match.begin(0) || 0
        open_paren = body.index("(", switch_start)
        next unless open_paren
        close_paren = JSRouteExtractor.find_matching_paren(body, open_paren)
        next unless close_paren
        expression = body[(open_paren + 1)...close_paren]
        kind = if expression_matches_ref?(expression, method_refs)
                 :method
               elsif expression_matches_ref?(expression, path_refs)
                 :path
               else
                 next
               end

        open_brace = body.index("{", close_paren)
        next unless open_brace
        close_brace = JSRouteExtractor.find_matching_brace(body, open_brace)
        next unless close_brace

        case_hits = [] of Tuple(Array(String), Int32)
        switch_body = body[(open_brace + 1)...close_brace]
        switch_body.scan(/\bcase\s*['"]([^'"]+)['"]\s*:/) do |case_match|
          raw_value = case_match[1]
          values = if kind == :method
                     method = normalize_method(raw_value)
                     method.empty? ? [] of String : [method]
                   else
                     path = normalize_path(raw_value)
                     path.empty? ? [] of String : [path]
                   end
          next if values.empty?

          case_start = open_brace + 1 + (case_match.begin(0) || 0)
          case_hits << {values, case_start}
        end

        case_hits.each_with_index do |(values, case_start), idx|
          # A case spans [case_start, next_case_start). Region membership in
          # `values_for_offset` is inclusive on both ends, so make the end
          # exclusive (next case start - 1) — otherwise the next case label is
          # treated as still inside this case and mis-scopes nested switches.
          case_end = if next_hit = case_hits[idx + 1]?
                       next_hit[1] - 1
                     else
                       close_brace
                     end
          yield kind, values, case_start, case_end
        end
      end
    end

    private def self.extract_methods(condition : String, refs : Array(String)) : Array(String)
      methods = [] of String
      refs.each do |ref|
        ref_re = ref_pattern(ref)
        condition.scan(/#{ref_re}(?:\s*\.\s*toUpperCase\s*\(\s*\))?\s*(?:===|==)\s*['"]([A-Za-z]+)['"]/i) do |match|
          method = normalize_method(match[1])
          methods << method unless method.empty?
        end
        condition.scan(/['"]([A-Za-z]+)['"]\s*(?:===|==)\s*#{ref_re}(?:\s*\.\s*toUpperCase\s*\(\s*\))?/i) do |match|
          method = normalize_method(match[1])
          methods << method unless method.empty?
        end
        condition.scan(/\[\s*([^\]]+)\]\s*\.\s*includes\s*\(\s*#{ref_re}\s*\)/i) do |match|
          match[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
            method = normalize_method(method_match[1])
            methods << method unless method.empty?
          end
        end
      end

      methods.uniq
    end

    private def self.extract_paths(condition : String, refs : Array(String)) : Array(String)
      paths = [] of String
      refs.each do |ref|
        ref_re = ref_pattern(ref)
        condition.scan(/#{ref_re}\s*(?:===|==)\s*['"`]([^'"`]+)['"`]/) do |match|
          path = normalize_path(match[1])
          paths << path unless path.empty?
        end
        condition.scan(/['"`]([^'"`]+)['"`]\s*(?:===|==)\s*#{ref_re}/) do |match|
          path = normalize_path(match[1])
          paths << path unless path.empty?
        end
        condition.scan(/#{ref_re}\s*\.\s*startsWith\s*\(\s*['"`]([^'"`]+)['"`]/) do |match|
          path = normalize_path(match[1])
          paths << path unless path.empty?
        end
        condition.scan(/\[\s*([^\]]+)\]\s*\.\s*includes\s*\(\s*#{ref_re}\s*\)/) do |match|
          match[1].scan(/['"`]([^'"`]+)['"`]/) do |path_match|
            path = normalize_path(path_match[1])
            paths << path unless path.empty?
          end
        end
      end

      paths.uniq
    end

    private def self.expression_matches_ref?(expression : String, refs : Array(String)) : Bool
      refs.any? do |ref|
        expression.matches?(/^\s*#{ref_pattern(ref)}\s*$/)
      end
    end

    private def self.ref_pattern(ref : String) : String
      if ref.includes?(".")
        ref.split(".").map { |part| Regex.escape(part) }.join("\\s*\\.\\s*")
      else
        "\\b#{Regex.escape(ref)}\\b"
      end
    end

    private def self.values_for_offset(regions : Array(Region), offset : Int32) : Array(String)
      values = [] of String
      regions.each do |region|
        next unless region.start_pos <= offset && offset <= region.end_pos

        region.values.each { |value| values << value unless values.includes?(value) }
      end
      values
    end

    private def self.method_hit_inside_path_region?(path_regions : Array(Region), method_hits : Array(ValueHit), path_hit : ValueHit) : Bool
      path_regions.any? do |region|
        next false unless region.start_pos <= path_hit.offset && path_hit.offset <= region.end_pos
        next false unless path_hit.values.any? { |path| region.values.includes?(path) }

        method_hits.any? { |method_hit| region.start_pos <= method_hit.offset && method_hit.offset <= region.end_pos }
      end
    end

    private def self.dedupe_route_hits(routes : Array(RouteHit)) : Array(RouteHit)
      result = [] of RouteHit
      seen = Set(Tuple(String, String)).new
      routes.each do |route|
        key = {route.method, route.path}
        next if seen.includes?(key)

        seen << key
        result << route
      end
      result
    end

    private def self.extract_params(handler : Handler, hit : RouteHit, endpoint : Endpoint) : Nil
      body = scoped_body(handler.body, hit.scope_start_pos, hit.scope_end_pos)
      if handler.request_name != "req"
        body = body.gsub(/\b#{Regex.escape(handler.request_name)}\s*\./, "req.")
      end

      JSRouteExtractor.extract_header_params(body, endpoint)
      JSRouteExtractor.extract_cookie_params(body, endpoint)
      extract_query_params(body, endpoint)
      extract_json_body_params(body, endpoint)
    end

    private def self.scoped_body(body : String, scope_start : Int32?, scope_end : Int32?) : String
      return body unless scope_start && scope_end
      return body unless scope_start >= 0 && scope_start < scope_end && scope_end <= body.size

      body[scope_start...scope_end]
    end

    private def self.extract_query_params(body : String, endpoint : Endpoint) : Nil
      body.scan(/\.\s*searchParams\s*\.\s*(?:get|getAll|has)\s*\(\s*['"]([^'"]+)['"]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query")) if match.size > 1
      end

      body.scan(/(?:const|let|var)\s+([A-Za-z_$]\w*)\s*=\s*new\s+URLSearchParams\s*\(/) do |match|
        next unless match.size > 1
        params_name = match[1]
        body.scan(/\b#{Regex.escape(params_name)}\s*\.\s*(?:get|getAll|has)\s*\(\s*['"]([^'"]+)['"]/) do |param_match|
          endpoint.push_param(Param.new(param_match[1], "", "query")) if param_match.size > 1
        end
      end

      body.scan(/\b[A-Za-z_$]\w*\s*\.\s*query\s*\.\s*([A-Za-z_$]\w*)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query")) if match.size > 1
      end

      body.scan(/\b[A-Za-z_$]\w*\s*\.\s*query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query")) if match.size > 1
      end
    end

    private def self.extract_json_body_params(body : String, endpoint : Endpoint) : Nil
      body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*JSON\s*\.\s*parse\s*\(/) do |match|
        next unless match.size > 1
        match[1].split(",").each do |raw_param|
          name = clean_destructured_param(raw_param)
          endpoint.push_param(Param.new(name, "", "json")) unless name.empty?
        end
      end

      body.scan(/JSON\s*\.\s*parse\s*\([^)]*\)\s*\.\s*([A-Za-z_$]\w*)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "json")) if match.size > 1
      end
    end

    private def self.clean_destructured_param(raw_param : String) : String
      param = raw_param.split("=", 2).first.strip
      param = param.lchop("...").strip
      param = param.split(":", 2).first.strip
      param = param[1..-2] if param.size >= 2 &&
                              ((param.starts_with?("'") && param.ends_with?("'")) ||
                              (param.starts_with?("\"") && param.ends_with?("\"")))
      return "" unless param.matches?(/^[A-Za-z_$]\w*$/)

      param
    end

    private def self.push_path_params(endpoint : Endpoint) : Nil
      endpoint.url.scan(/:(\w+)/) do |match|
        next unless match.size > 1
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    private def self.normalize_method(raw_method : String) : String
      method = raw_method.upcase
      method = "DELETE" if method == "DEL"
      HTTP_METHODS.includes?(method) ? method : ""
    end

    private def self.normalize_path(raw_path : String) : String
      path = raw_path.strip
      return "" unless path.starts_with?("/")
      return "" if path.includes?("${")
      return "" if path.includes?(" ")
      return "" if path.size > 300

      path = path.split("?", 2).first
      path = path.split("#", 2).first
      path = path.gsub(/\/+/, "/")
      path = path[0...-1] if path.ends_with?("/") && path != "/"
      path.empty? ? "/" : path
    end

    private def self.split_top_level_args(content : String, start_pos : Int32, end_pos : Int32) : Array(Tuple(String, Int32))
      split_top_level(content, start_pos, end_pos, ',')
    end

    private def self.split_top_level(content : String, start_pos : Int32, end_pos : Int32, delimiter : Char) : Array(Tuple(String, Int32))
      args = [] of Tuple(String, Int32)
      arg_start = start_pos
      depth = 0
      quote : Char? = nil
      escaped = false
      i = start_pos

      while i < end_pos
        char = content[i]
        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          i += 1
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when delimiter
          if depth == 0
            args << normalized_arg(content, arg_start, i)
            arg_start = i + 1
          end
        end
        i += 1
      end

      args << normalized_arg(content, arg_start, end_pos)
      args
    end

    private def self.normalized_arg(content : String, start_pos : Int32, end_pos : Int32) : Tuple(String, Int32)
      start_idx = skip_whitespace(content, start_pos)
      stop_idx = end_pos
      while stop_idx > start_idx && content[stop_idx - 1].whitespace?
        stop_idx -= 1
      end

      {content[start_idx...stop_idx], start_idx}
    end

    private def self.skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    private def self.identifier_char?(char : Char) : Bool
      char.ascii_letter? || char.ascii_number? || char == '_' || char == '$'
    end

    private def self.line_for_pos(content : String, pos : Int32) : Int32
      content[0...pos].count('\n') + 1
    end
  end
end
