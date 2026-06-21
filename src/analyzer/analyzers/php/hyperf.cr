require "../../engines/php_engine"

module Analyzer::Php
  class Hyperf < PhpEngine
    private struct ClassRoutePrefix
      getter path, body_start, body_end

      def initialize(@path : String, @body_start : Int32, @body_end : Int32)
      end
    end

    HTTP_MAPPING_ATTRIBUTES = {
      "GetMapping"     => "GET",
      "PostMapping"    => "POST",
      "PutMapping"     => "PUT",
      "PatchMapping"   => "PATCH",
      "DeleteMapping"  => "DELETE",
      "OptionsMapping" => "OPTIONS",
      "HeadMapping"    => "HEAD",
    }

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        next unless hyperf_relevant?(content)

        endpoints.concat(analyze_annotation_routes(content, path, include_callee))
        endpoints.concat(analyze_procedural_routes(content, "", path, include_callee))
      end

      endpoints
    end

    # Cheap pre-filter: avoids heavy regex work on PHP files that clearly
    # aren't part of a Hyperf project. Project-wide scans still feed unrelated
    # PHP through this analyzer.
    private def hyperf_relevant?(content : String) : Bool
      content.includes?("Hyperf\\") ||
        content.includes?("Hyperf\\HttpServer") ||
        !!content.match(/\bRouter::(?:get|post|put|patch|delete|options|head|addRoute|addGroup)\s*\(/i) ||
        !!content.match(/#\[\s*(?:AutoController|Controller|Get|Post|Put|Patch|Delete|Options|Head|RequestMapping)/)
    end

    # --- Annotation-based routes (PHP 8 attributes) ---------------------------

    private def analyze_annotation_routes(content : String, path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      class_prefixes = extract_class_route_prefixes(content)

      offset = 0
      attribute_regex = /#\[\s*(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|OptionsMapping|HeadMapping|RequestMapping)\s*\(([^)]*)\)\s*\]/m

      while m = content.match(attribute_regex, offset)
        attr_text = m[0]
        attr_name = m[1]
        attr_args = m[2]

        attr_start = content.index(attr_text, offset)
        break unless attr_start
        offset = attr_start + attr_text.size

        next if attribute_applies_to_class?(content, offset)

        route_path = extract_attribute_path(attr_args)
        next unless route_path

        methods =
          if attr_name == "RequestMapping"
            methods_from_request_mapping(attr_args)
          else
            [HTTP_MAPPING_ATTRIBUTES[attr_name]]
          end
        methods = ["GET"] if methods.empty?

        method_body = extract_php_method_body_after(content, attr_start)

        full_path = build_full_path(class_prefix_for_position(class_prefixes, attr_start), route_path)
        params = extract_brace_path_params(full_path)
        if method_body
          params.concat(extract_method_param_attributes(content, attr_start))
          params.concat(extract_method_params(method_body[0]))
        end
        params = dedup_params(params)

        details = Details.new(PathInfo.new(path))
        methods.each do |method|
          endpoint = Endpoint.new(full_path, method.upcase, params, details)
          attach_method_callees(endpoint, method_body, path) if include_callee
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def extract_class_route_prefixes(content : String) : Array(ClassRoutePrefix)
      prefixes = [] of ClassRoutePrefix
      class_regex = /\bclass\s+\w+[^{]*\{/m
      offset = 0

      while class_match = content.match(class_regex, offset)
        class_start = class_match.begin(0)
        brace_pos = class_match.end(0) - 1
        class_end = find_matching_php_close_brace(content, brace_pos)
        if class_end
          prefix = controller_prefix_before_class(content, class_start)
          prefixes << ClassRoutePrefix.new(prefix, brace_pos + 1, class_end) if prefix
          offset = class_end + 1
        else
          offset = class_match.end(0)
        end
      end

      prefixes
    end

    private def controller_prefix_before_class(content : String, class_start : Int32) : String?
      lookbehind_start = Math.max(0, class_start - 800)
      prelude = content[lookbehind_start...class_start]

      if attr_match = prelude.match(/#\[\s*(?:AutoController|Controller)\s*\(([^)]*)\)\s*\][^\n]*\n[^\n]*\z/m)
        return extract_attribute_path(attr_match[1]) || ""
      end

      return "" if prelude.match(/#\[\s*(?:AutoController|Controller)\s*\]\s*$/m)

      nil
    end

    private def attribute_applies_to_class?(content : String, attr_end : Int32) : Bool
      next_target = content.match(/\b(class|function|public\s+function|private\s+function|protected\s+function)\b/m, attr_end)
      return false unless next_target

      next_target[1] == "class"
    end

    private def class_prefix_for_position(prefixes : Array(ClassRoutePrefix), pos : Int32) : String
      prefix = prefixes.find { |class_prefix| pos >= class_prefix.body_start && pos < class_prefix.body_end }
      prefix ? prefix.path : ""
    end

    private def extract_attribute_path(args : String) : String?
      if m = args.match(/(?:^|[,(]\s*)path\s*[:=]\s*['"]([^'"]+)['"]/i)
        return m[1]
      end

      if m = args.match(/(?:^|[,(]\s*)prefix\s*[:=]\s*['"]([^'"]+)['"]/i)
        return m[1]
      end

      if m = args.match(/^\s*['"]([^'"]+)['"]/)
        return m[1]
      end

      nil
    end

    private def methods_from_request_mapping(args : String) : Array(String)
      methods = [] of String

      # methods: "GET,POST" or methods="GET, DELETE"
      if m = args.match(/methods\s*[:=]\s*['"]([^'"]+)['"]/i)
        m[1].split(",").each do |verb|
          v = verb.strip.upcase
          methods << v unless v.empty?
        end
        return methods
      end

      # methods: ["GET","POST"] / methods={"GET", "POST"}
      if m = args.match(/methods\s*[:=]\s*[\[\{]([^\]\}]+)[\]\}]/i)
        m[1].scan(/['"]([^'"]+)['"]/).each do |sub|
          methods << sub[1].upcase
        end
      end

      methods
    end

    # Parameters declared via #[RequestParam], #[RequestBody], #[Header],
    # #[Cookie] attributes attached to method arguments. Walk forward from
    # the mapping attribute to the next method body and pick up any param
    # attributes that appear in between.
    private def extract_method_param_attributes(content : String, attr_start : Int32) : Array(Param)
      params = [] of Param
      search_end = content.index('{', attr_start)
      return params unless search_end

      region = content[attr_start...search_end]

      param_attr_regex = /#\[\s*(RequestParam|RequestBody|Param|Header|Cookie)(?:\s*\(([^)]*)\))?\s*\]\s*[^,)]*?(?:\$(\w+))?/m
      region.scan(param_attr_regex) do |m|
        attr_name = m[1]
        attr_args = m[2]?
        var_name = m[3]?

        explicit_name = attr_args ? extract_attribute_name_value(attr_args) : nil
        name = explicit_name || var_name
        next unless name

        param_type =
          case attr_name
          when "RequestBody" then "form"
          when "Header"      then "header"
          when "Cookie"      then "cookie"
          else                    "query"
          end

        params << Param.new(name, "", param_type)
      end

      params
    end

    private def extract_attribute_name_value(args : String) : String?
      if m = args.match(/(?:^|[,(]\s*)name\s*[:=]\s*['"]([^'"]+)['"]/i)
        return m[1]
      end

      if m = args.match(/(?:^|[,(]\s*)key\s*[:=]\s*['"]([^'"]+)['"]/i)
        return m[1]
      end

      if m = args.match(/^\s*['"]([^'"]+)['"]/)
        return m[1]
      end

      nil
    end

    # --- Procedural routes (Router::get / Router::addGroup) -------------------

    private def analyze_procedural_routes(content : String,
                                          prefix : String,
                                          file_path : String,
                                          include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      working_content = content

      # 1. Expand Router::addGroup('/prefix', function () { ... }) recursively.
      loop do
        info = find_group_call(working_content)
        break unless info

        match_start, after_open_brace, body_end, close_end, group_prefix = info
        group_body = working_content[after_open_brace...body_end]
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_procedural_routes(group_body, new_prefix, file_path, include_callee))

        replacement = "\n" * working_content[match_start...close_end].count('\n')
        working_content = working_content[0...match_start] + replacement + working_content[close_end..]
      end

      # 2. Router::get/post/...('/path', handler)
      verb_regex = /\bRouter::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/i
      working_content.scan(verb_regex) do |m|
        method = m[1].upcase
        route_path = m[2]
        full_path = build_full_path(prefix, route_path)
        params = extract_brace_path_params(full_path)
        endpoints << Endpoint.new(full_path, method, dedup_params(params), details.dup)
      end

      # 3. Router::addRoute(['GET','POST'], '/path', handler) — also matches
      #    Router::addRoute('GET', ...). The methods spec is captured up to
      #    the closing `]` / `}` or first comma for the string form.
      add_route_regex = /\bRouter::addRoute\s*\(\s*((?:\[[^\]]*\]|\{[^}]*\}|['"][^'"]*['"]))\s*,\s*['"]([^'"]+)['"]\s*,/i
      working_content.scan(add_route_regex) do |m|
        methods = extract_add_route_methods(m[1])
        next if methods.empty?

        route_path = m[2]
        full_path = build_full_path(prefix, route_path)
        params = extract_brace_path_params(full_path)
        methods.each do |verb|
          endpoints << Endpoint.new(full_path, verb.upcase, dedup_params(params), details.dup)
        end
      end

      endpoints
    end

    private def extract_add_route_methods(spec : String) : Array(String)
      methods = [] of String
      stripped = spec.strip

      # Array form: ['GET','POST'] or ["GET","POST"]
      if stripped.starts_with?('[') || stripped.starts_with?('{')
        stripped.scan(/['"]([^'"]+)['"]/) do |m|
          methods << m[1].upcase
        end
        return methods
      end

      # Single string form: 'GET'
      if m = stripped.match(/['"]([^'"]+)['"]/)
        methods << m[1].upcase
      end

      methods
    end

    # Locate the first `Router::addGroup("/prefix", function() { ... })` call.
    private def find_group_call(content : String) : Tuple(Int32, Int32, Int32, Int32, String)?
      regex = /\bRouter::addGroup\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      m = content.match(regex)
      return unless m

      match_text = m[0]
      match_start = content.index(match_text)
      return unless match_start

      brace_pos = match_start + match_text.size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return unless body_end

      close_end = body_end + 1
      while close_end < content.size && content[close_end].ascii_whitespace?
        close_end += 1
      end
      if close_end < content.size && content[close_end] == ')'
        close_end += 1
        if close_end < content.size && content[close_end] == ';'
          close_end += 1
        end
      end

      {match_start, brace_pos + 1, body_end, close_end, m[1]}
    end

    # --- Callees + method body param extraction -------------------------------

    private def attach_method_callees(endpoint : Endpoint, method_body : Tuple(String, Int32)?, path : String)
      return unless method_body

      body, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_method_params(method_body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      patterns = [
        {/\$request->input\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "query"},
        {/\$request->query\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "query"},
        {/\$request->post\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "form"},
        {/\$request->json\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "json"},
        {/\$request->header\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "header"},
        {/\$request->cookie\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "cookie"},
        {/\$request->file\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/, "file"},
      ]

      patterns.each do |entry|
        pattern, type = entry
        method_body.scan(pattern) do |m|
          name = m[1]
          key = "#{type}:#{name}"
          next if seen.includes?(key)
          params << Param.new(name, "", type)
          seen.add(key)
        end
      end

      params
    end

    private def dedup_params(params : Array(Param)) : Array(Param)
      seen = Set(String).new
      params.select do |param|
        key = "#{param.param_type}\0#{param.name}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end
  end
end
