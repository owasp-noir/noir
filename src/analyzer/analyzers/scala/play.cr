require "../../../models/analyzer"
require "../../../miniparsers/scala_callee_extractor"

module Analyzer::Scala
  class Play < Analyzer
    # Stores parsed controller methods with their parameters
    alias ControllerMethod = NamedTuple(headers: Array(String), cookies: Array(String), body_type: String?, callees: Array(Noir::ScalaCalleeExtractor::Entry))
    alias ScopedKey = Tuple(String, String)
    alias MethodRegion = NamedTuple(signature: String, body: String, body_start: Int32)

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the `def <name>` matcher interpolates a
    # discovered method name, so memoize it per name instead of rebuilding
    # it for every action lookup.
    @method_def_regexes = Hash(String, Regex).new

    def analyze
      file_list = all_files()
      routes_files = [] of String
      scala_files = [] of String
      @scala_paths = [] of String

      # First pass: find all routes files and Scala controller files
      file_list.each do |path|
        next unless File.exists?(path)
        # Skip test sources: Play's own repo parks ~300 phantom
        # endpoints in `dev-mode/sbt-plugin/src/sbt-test/.../conf/routes`
        # (sbt-plugin test fixtures) and `dev-mode/play-routes-compiler/
        # src/test/resources/*.routes`. Both `/src/test/` (Maven/Gradle
        # convention) and `/src/sbt-test/` (sbt-plugin's per-fixture
        # test trees) are unambiguous — production code never adopts
        # either.
        next if path.includes?("/src/test/") || path.includes?("/src/sbt-test/")

        if path.ends_with?("routes") || path.ends_with?("routes.conf") || path.includes?("/conf/routes")
          routes_files << path
        elsif path.ends_with?(".scala")
          @scala_paths << path
          scala_files << path if play_controller_file?(path)
        end
      end

      # Parse controller files to build method map
      controller_methods = parse_controller_files(scala_files)
      routes_by_key = index_routes_files(routes_files)
      included_routes = collect_included_routes(routes_files, routes_by_key)
      top_level_routes = routes_files.reject { |path| included_routes.includes?(path) }
      top_level_routes = routes_files if top_level_routes.empty?

      # Process each routes file
      top_level_routes.each do |routes_path|
        process_routes_file(routes_path, controller_methods, routes_by_key, "", Set(String).new)
      end

      Fiber.yield
      @result
    end

    # All `.scala` paths in the scan, used to resolve SIRD/SimpleRouter
    # classes referenced from `->` include lines that are not routes files.
    @scala_paths = [] of String

    # Decide whether a `.scala` file holds Play controllers. The
    # `controllers` package is conventional, but Play resolves actions
    # by the fully-qualified name in the `routes` file, so controllers
    # routinely live in other packages. Gating on the `play.api.mvc`
    # marker recovers those — otherwise their header/cookie/body params
    # and callees are dropped. SIRD/SimpleRouter resolution still walks
    # every `.scala` path via `@scala_paths`, so this only governs the
    # controller-method enrichment map.
    private def play_controller_file?(path : String) : Bool
      return true if path.includes?("/controllers/")
      read_file_content(path).includes?("play.api.mvc")
    end

    # Parse Scala controller files to extract header, cookie, and body parameters
    private def parse_controller_files(scala_files : Array(String)) : Hash(ScopedKey, ControllerMethod)
      controller_methods = Hash(ScopedKey, ControllerMethod).new
      want_callees = callees_needed?

      scala_files.each do |path|
        content = read_file_content(path)
        base_path = configured_base_for(path)
        # Length-preserving copy with strings/comments blanked out. Braces,
        # colons and `def` keywords that live inside literals or comments are
        # turned into spaces, so the structural scan below never trips on
        # them. Indices computed on `structure` map 1:1 onto `content`, so the
        # body text handed to the callee extractor is always real source.
        structure = blank_non_code(content)

        # Extract package name
        package_name = ""
        if pkg_match = content.match(/package\s+([\w.]+)/)
          package_name = pkg_match[1]
        end

        # Find every class/object/trait. Modern Play controllers are written
        # in Scala 3 with significant indentation (`class Foo(...) extends
        # Bar:`) and no braces, so brace-based detection misses them entirely.
        declarations = class_declarations(structure)
        declarations.each_with_index do |decl, decl_index|
          class_name, class_start = decl
          class_end = decl_index + 1 < declarations.size ? declarations[decl_index + 1][1] : content.size
          class_struct = structure[class_start...class_end]
          class_src = content[class_start...class_end]

          # Find all def methods in the class. Route files decide whether a
          # method is externally reachable, so parsing custom ActionBuilder
          # wrappers here improves controller parameter enrichment without
          # adding standalone endpoints.
          seen_methods = Set(String).new
          class_struct.scan(/\bdef\s+(\w+)/) do |match|
            method_name = match[1]
            next unless seen_methods.add?(method_name)

            # Delimit the method body by indentation + bracket balance so that
            # both brace blocks (`= Action { ... }`) and Scala 3 colon blocks
            # (`= Open:` / `= AuthOrScoped():`) are captured precisely, instead
            # of grabbing a later sibling method's brace block.
            region = extract_method_body(class_struct, class_src, method_name)
            next unless region

            method_body = region[:body]
            method_signature = region[:signature]

            headers = [] of String
            cookies = [] of String
            body_type : String? = nil

            # Extract headers: request.headers.get("Header-Name") or request.headers("Header-Name")
            method_body.scan(/request\s*\.\s*headers(?:\s*\.\s*get)?\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
              headers << header_match[1] unless headers.includes?(header_match[1])
            end

            # Also match implicit request patterns: headers.get("Header-Name")
            method_body.scan(/headers\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |header_match|
              headers << header_match[1] unless headers.includes?(header_match[1])
            end

            # Extract cookies: request.cookies.get("cookie-name")
            method_body.scan(/request\s*\.\s*cookies\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |cookie_match|
              cookies << cookie_match[1] unless cookies.includes?(cookie_match[1])
            end

            # Also match: cookies.get("cookie-name")
            method_body.scan(/cookies\s*\.\s*get\s*\(\s*["']([^"']+)["']\s*\)/) do |cookie_match|
              cookies << cookie_match[1] unless cookies.includes?(cookie_match[1])
            end

            # Extract body type: request.body.asJson, request.body.asFormUrlEncoded, parse.json, parse.form
            body_source = "#{method_signature}\n#{method_body}"
            if body_source.match(/request\s*\.\s*body\s*\.\s*asJson|parse\s*\.\s*json|Json\s*\.\s*parse|\.body\s*\.\s*asJson|\.body\s*\.\s*asOpt|\.body\s*\.\s*as\s*\[/)
              body_type = "json"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*as(?:FormUrlEncoded|MultipartFormData)|parse\s*\.\s*(?:form|multipartFormData|tolerantFormUrlEncoded)/)
              body_type = "form"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*asXml|parse\s*\.\s*(?:xml|tolerantXml)/)
              body_type = "xml"
            elsif body_source.match(/request\s*\.\s*body\s*\.\s*as(?:Text|Raw|Bytes)|parse\s*\.\s*(?:text|raw|tolerantText)/)
              body_type = "body"
            end

            full_method_name = package_name.empty? ? "#{class_name}.#{method_name}" : "#{package_name}.#{class_name}.#{method_name}"

            callees = if want_callees
                        start_line = line_at(content, class_start + region[:body_start])
                        Noir::ScalaCalleeExtractor.callees_for_body(method_body, path, start_line)
                      else
                        [] of Noir::ScalaCalleeExtractor::Entry
                      end
            controller_methods[{base_path, full_method_name}] = {headers: headers, cookies: cookies, body_type: body_type, callees: callees}
          end
        end
      end

      controller_methods
    end

    # Blank out strings and comments while preserving the byte length and line
    # structure of the source, so structural offsets stay aligned.
    private def blank_non_code(content : String) : String
      block_depth = 0
      in_multiline_string = false
      builder = String::Builder.new
      lines = content.split('\n')
      lines.each_with_index do |line, index|
        stripped, block_depth, in_multiline_string = Noir::ScalaCalleeExtractor.strip_non_code_with_state(line, block_depth, in_multiline_string)
        builder << stripped
        builder << '\n' unless index == lines.size - 1
      end
      builder.to_s
    end

    # Locate class/object/trait declarations (Scala 2 brace style and Scala 3
    # indentation style alike). Returns {name, start_offset} pairs in order.
    private def class_declarations(structure : String) : Array(Tuple(String, Int32))
      decls = [] of Tuple(String, Int32)
      structure.scan(/(?:\A|\n)[ \t]*((?:(?:final|sealed|abstract|case|implicit|private|protected|open)[ \t]+)*(?:class|object|trait)[ \t]+(\w+))/) do |match|
        name = match[2]
        next if name.empty?
        decls << {name, match.begin(1) || 0}
      end
      decls
    end

    # Extract a method's signature and body. The body excludes the leading
    # action-builder wrapper (`Action`, `Open`, `Auth`, custom builders) so it
    # is not reported as a callee, matching brace-style behavior.
    private def extract_method_body(structure : String, source : String, method_name : String) : MethodRegion?
      method_def_regex = @method_def_regexes[method_name] ||= /\bdef\s+#{Regex.escape(method_name)}(?![A-Za-z0-9_$])/
      match = structure.match(method_def_regex)
      return unless match
      def_start = match.begin(0) || 0
      cursor = match.end(0)
      return unless cursor

      def_line_start = structure.rindex('\n', def_start)
      def_line_start = def_line_start ? def_line_start + 1 : 0
      def_line_end = structure.index('\n', def_start) || structure.size
      base_indent = leading_indent_of(structure[def_line_start...def_line_end])

      region_end = method_region_end(structure, def_line_start, base_indent)

      # The `=` that introduces the body: skip type params, parameter lists and
      # default-value `=` (all of which sit inside brackets), and ignore `=>`.
      eq_index = locate_body_eq(structure, cursor, region_end)

      # Find the body separator: the first top-level `{` (brace block) or an
      # end-of-line `:` (Scala 3 indented block).
      search_from = eq_index ? eq_index + 1 : cursor
      sep_index = nil
      sep_kind = :expr
      depth = 0
      i = search_from
      while i < region_end
        c = structure[i]
        if depth == 0
          if c == '{'
            sep_index = i
            sep_kind = :brace
            break
          elsif c == ':' && rest_of_line_blank?(structure, i + 1, region_end)
            sep_index = i
            sep_kind = :colon
            break
          end
        end
        case c
        when '(', '[', '{' then depth += 1
        when ')', ']', '}' then depth -= 1 if depth > 0
        end
        i += 1
      end

      case sep_kind
      when :brace
        # `sep_index` is always set when `sep_kind` is `:brace`/`:colon`; the
        # `if` narrows the type so we avoid `not_nil!`.
        if open_brace = sep_index
          close = matching_brace(structure, open_brace)
          body_start = open_brace + 1
          body_end = close || region_end
          {signature: source[def_start..open_brace], body: source[body_start...body_end], body_start: body_start}
        end
      when :colon
        if colon = sep_index
          body_start = colon + 1
          {signature: source[def_start..colon], body: source[body_start...region_end], body_start: body_start}
        end
      else
        # Single-expression body (`def foo = bar(x)`). Without a `=` there is no
        # value body to parse (e.g. an abstract def).
        return unless eq_index
        body_start = skip_whitespace(structure, eq_index + 1, region_end)
        {signature: source[def_start..eq_index], body: source[body_start...region_end], body_start: body_start}
      end
    end

    # Walk forward from the def line; the region ends at the first non-blank
    # line that dedents to <= the def's indentation while no bracket is open.
    private def method_region_end(structure : String, def_line_start : Int32, base_indent : Int32) : Int32
      size = structure.size
      depth = 0
      first_line = true
      line_start = def_line_start
      while line_start < size
        line_end = structure.index('\n', line_start) || size
        line = structure[line_start...line_end]
        unless first_line
          if depth == 0 && !line.strip.empty? && leading_indent_of(line) <= base_indent
            return line_start
          end
        end
        depth += bracket_delta(line)
        depth = 0 if depth < 0
        first_line = false
        line_start = line_end + 1
      end
      size
    end

    # Index of the top-level `=` that begins the method body, or nil.
    private def locate_body_eq(structure : String, from : Int32, region_end : Int32) : Int32?
      depth = 0
      i = from
      while i < region_end
        c = structure[i]
        if depth == 0
          if c == '='
            nxt = structure[i + 1]?
            # Guard the index explicitly: Crystal's `[-1]?` wraps to the last
            # char rather than returning nil.
            prv = i > 0 ? structure[i - 1]? : nil
            return i if nxt != '>' && nxt != '=' && prv != '=' && prv != '!' && prv != '<' && prv != '>'
          elsif c == '{'
            # Brace-only body (procedure syntax `def foo { ... }`): no `=`.
            return
          end
        end
        case c
        when '(', '[', '{' then depth += 1
        when ')', ']', '}' then depth -= 1 if depth > 0
        end
        i += 1
      end
      nil
    end

    # Index of the brace matching the one at `open_index`, or nil.
    private def matching_brace(structure : String, open_index : Int32) : Int32?
      depth = 0
      i = open_index
      size = structure.size
      while i < size
        case structure[i]
        when '{' then depth += 1
        when '}'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    private def rest_of_line_blank?(structure : String, from : Int32, region_end : Int32) : Bool
      i = from
      while i < region_end
        c = structure[i]
        break if c == '\n'
        return false unless c == ' ' || c == '\t' || c == '\r'
        i += 1
      end
      true
    end

    private def skip_whitespace(structure : String, from : Int32, region_end : Int32) : Int32
      i = from
      while i < region_end
        c = structure[i]
        break unless c == ' ' || c == '\t' || c == '\n' || c == '\r'
        i += 1
      end
      i
    end

    private def leading_indent_of(line : String) : Int32
      count = 0
      line.each_char do |c|
        break unless c == ' ' || c == '\t'
        count += 1
      end
      count
    end

    private def bracket_delta(text : String) : Int32
      delta = 0
      text.each_char do |c|
        case c
        when '(', '[', '{' then delta += 1
        when ')', ']', '}' then delta -= 1
        end
      end
      delta
    end

    private def line_at(content : String, index : Int32) : Int32
      return 1 if index <= 0
      limit = index > content.size ? content.size : index
      content[0, limit].count('\n') + 1
    end

    # Process a Play routes file
    private def process_routes_file(path : String,
                                    controller_methods : Hash(ScopedKey, ControllerMethod),
                                    routes_by_key : Hash(ScopedKey, Array(String)),
                                    prefix : String,
                                    seen : Set(String))
      return if seen.includes?(path)

      seen << path
      content = read_file_content(path)
      lines = content.split('\n')

      lines.each_with_index do |line, index|
        stripped_line = line.strip

        # Skip comments and empty lines
        next if stripped_line.empty? || stripped_line.starts_with?("#")

        if include_match = stripped_line.match(/^->\s+([^\s]+)\s+(.+)$/)
          include_prefix = include_match[1]
          include_target = include_match[2]
          if included_path = resolve_included_routes_file(include_target, routes_by_key, path)
            process_routes_file(included_path, controller_methods, routes_by_key, join_paths(prefix, include_prefix), seen)
          elsif router = resolve_sird_router(include_target, path)
            # The include target is a programmatic SIRD router class
            # (`-> /v1/posts v1.post.PostRouter`), not a routes file.
            process_sird_router(router, join_paths(prefix, include_prefix))
          end
          next
        end

        # Match route definitions: METHOD /path controller.action
        # Example: GET /users/:id controllers.Users.show(id: Long)
        if route_match = stripped_line.match(/^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+([^\s]+)\s+(.+)/)
          method = route_match[1]
          route_path = join_included_route(prefix, route_match[2])
          action = route_match[3]

          endpoint = create_endpoint(route_path, method, path, index + 1)

          # Extract path parameters
          extract_path_params(endpoint, route_path)

          # Extract query parameters from action signature
          extract_params_from_action(endpoint, action)

          # Extract controller method name and add header/cookie/body params
          extract_controller_params(endpoint, action, controller_methods, path)

          @result << endpoint
        end
      end

      seen.delete(path)
    end

    private def index_routes_files(routes_files : Array(String)) : Hash(ScopedKey, Array(String))
      index = Hash(ScopedKey, Array(String)).new { |hash, key| hash[key] = [] of String }

      routes_files.each do |path|
        base_path = configured_base_for(path)
        basename = File.basename(path)
        index[{base_path, basename}] << path

        if basename == "routes" || basename == "routes.conf"
          index[{base_path, "Routes"}] << path
          index[{base_path, "router.Routes"}] << path
        elsif match = basename.match(/^(.+)\.routes$/)
          name = match[1]
          index[{base_path, name}] << path
          index[{base_path, "#{name}.Routes"}] << path
        end
      end

      index
    end

    private def collect_included_routes(routes_files : Array(String), routes_by_key : Hash(ScopedKey, Array(String))) : Set(String)
      included = Set(String).new

      routes_files.each do |path|
        read_file_content(path).each_line do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?("#")
          next unless include_match = stripped.match(/^->\s+[^\s]+\s+(.+)$/)

          if included_path = resolve_included_routes_file(include_match[1], routes_by_key, path)
            included << included_path
          end
        end
      end

      included
    end

    private def resolve_included_routes_file(target : String,
                                             routes_by_key : Hash(ScopedKey, Array(String)),
                                             including_path : String) : String?
      key = target.split(/\s|\(/).first.strip
      key = key.lchop("@")
      candidates = [key]

      if key.ends_with?(".Routes")
        candidates << key[0...(key.size - ".Routes".size)]
      else
        candidates << "#{key}.Routes"
      end

      including_dir = File.dirname(including_path)
      including_base = configured_base_for(including_path)
      candidates.each do |candidate|
        paths = routes_by_key[{including_base, candidate}]?
        next unless paths

        if local_path = paths.find { |path| File.dirname(path) == including_dir }
          return local_path
        end
      end

      candidates.each do |candidate|
        paths = routes_by_key[{including_base, candidate}]?
        return paths.first if paths && paths.size == 1
      end

      nil
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    # Join a mount prefix onto a route defined in an included routes file, but
    # don't double the prefix when the included file already carries it.
    # Standard Play sub-routes are relative (`-> /appeal appeal.Routes` over
    # `GET /landing` → `/appeal/landing`), but large apps such as lila write the
    # full path in the sub-file (`GET /appeal/landing`), where prepending again
    # would yield `/appeal/appeal/landing`. The boundary check (exact match or
    # `prefix/…`) keeps a coincidental relative path like `/appeals` prefixed.
    private def join_included_route(prefix : String, suffix : String) : String
      return join_paths(prefix, suffix) if prefix.empty?

      normalized_prefix = prefix.rstrip('/')
      normalized_suffix = suffix.starts_with?('/') ? suffix : "/#{suffix}"
      if normalized_suffix == normalized_prefix || normalized_suffix.starts_with?("#{normalized_prefix}/")
        return normalized_suffix
      end

      join_paths(prefix, suffix)
    end

    # Extract path parameters from route pattern
    private def extract_path_params(endpoint : Endpoint, route_path : String)
      # Match :param style parameters
      route_path.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end

      # Match $param<regex> style parameters
      route_path.scan(/\$(\w+)<[^>]+>/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end

      # Match *param wildcard style parameters
      route_path.scan(/\*(\w+)/) do |match|
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end
    end

    # Extract query parameters from action signature
    # Example: controllers.Users.show(id: Long, name: String ?= "default")
    private def extract_params_from_action(endpoint : Endpoint, action : String)
      # Extract parameters from action signature
      if params_match = action.match(/\((.*)\)/)
        params_str = params_match[1]

        split_route_action_params(params_str).each do |param_def|
          param_def = param_def.strip
          next if param_def.empty?

          if route_param = route_action_param(param_def)
            param_name, param_type, default_value = route_param
            next if request_route_param_type?(param_type)
            next if endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            next if endpoint.params.any? { |p| p.name == param_name }

            endpoint.push_param(Param.new(param_name, default_value, "query"))
          end
        end
      end
    end

    private def split_route_action_params(params_str : String) : Array(String)
      params = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      params_str.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          next unless depth == 0

          params << params_str[start...index].strip
          start = index + 1
        end
      end

      tail = params_str[start..]?.to_s.strip
      params << tail unless tail.empty?
      params
    end

    private def route_action_param(param_def : String) : Tuple(String, String?, String)?
      optional_default_index = top_level_operator_index(param_def, "?=")
      fixed_value_index = top_level_operator_index(param_def, "=")
      return if fixed_value_index && optional_default_index.nil?

      declaration_end = optional_default_index || param_def.size
      declaration = param_def[0...declaration_end].strip
      return if declaration.empty?

      default_value = ""
      if optional_default_index
        raw_default = param_def[(optional_default_index + 2)..].strip
        default_value = normalize_route_default_value(raw_default)
      end

      if colon = declaration.index(':')
        name = declaration[0...colon].strip
        type_name = declaration[(colon + 1)..].strip
        return if name.empty?
        return {name, type_name.empty? ? nil : type_name, default_value}
      end

      name = declaration.strip
      return unless name.match(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      {name, nil, default_value}
    end

    private def top_level_operator_index(text : String, operator : String) : Int32?
      depth = 0
      in_string = false
      quote = '\0'
      escape = false
      i = 0

      while i <= text.size - operator.size
        char = text[i]

        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          i += 1
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        else
          # `i` is a CHAR index; char-slice (byte_slice would treat i as a byte
          # offset and desync the match when a multi-byte char precedes it).
          return i if depth == 0 && text[i, operator.size]? == operator
        end
        i += 1
      end

      nil
    end

    private def normalize_route_default_value(raw_default : String) : String
      value = raw_default.strip
      return "" if value.empty?

      if value.size >= 2 && ((value.starts_with?('"') && value.ends_with?('"')) || (value.starts_with?("'") && value.ends_with?("'")))
        return value[1..-2]
      end

      value
    end

    private def request_route_param_type?(param_type : String?) : Bool
      return false unless param_type

      normalized = param_type.gsub(/\s+/, "")
      normalized == "Request" || normalized == "RequestHeader" || normalized == "MessagesRequest" ||
        normalized.ends_with?(".Request") || normalized.ends_with?(".RequestHeader") || normalized.ends_with?(".MessagesRequest")
    end

    # Extract header, cookie, and body parameters from controller method
    private def extract_controller_params(endpoint : Endpoint,
                                          action : String,
                                          controller_methods : Hash(ScopedKey, ControllerMethod),
                                          routes_path : String)
      # Extract controller method name from action
      # Example: controllers.Users.show(id: Long) -> controllers.Users.show
      method_name = action.split("(").first.strip.lchop("@")

      # Look up the controller method
      if method_info = controller_methods[{configured_base_for(routes_path), method_name}]?
        # Add header parameters
        method_info[:headers].each do |header|
          unless endpoint.params.any? { |p| p.name == header && p.param_type == "header" }
            endpoint.push_param(Param.new(header, "", "header"))
          end
        end

        # Add cookie parameters
        method_info[:cookies].each do |cookie|
          unless endpoint.params.any? { |p| p.name == cookie && p.param_type == "cookie" }
            endpoint.push_param(Param.new(cookie, "", "cookie"))
          end
        end

        # Add body parameter if body type detected
        if body_type = method_info[:body_type]
          unless endpoint.params.any? { |p| p.name == "body" }
            endpoint.push_param(Param.new("body", "", body_type))
          end
        end

        method_info[:callees].each do |name, path, line|
          endpoint.push_callee(Callee.new(name, path: path, line: line))
        end
      end
    end

    # Resolve an `->` include target to a programmatic SIRD router class file.
    # Play lets routes delegate to a `SimpleRouter`/`Router` whose routing is a
    # PartialFunction (`-> /v1/posts v1.post.PostRouter`); these never resolve
    # to a `.routes` file, so the routes-file pass alone misses every endpoint.
    private def resolve_sird_router(target : String, including_path : String) : NamedTuple(path: String, content: String, class_name: String)?
      return if @scala_paths.empty?

      key = target.split(/\s|\(/).first.strip.lchop("@")
      class_name = key.split(".").last
      return if class_name.empty?

      filename = "#{class_name}.scala"
      including_base = configured_base_for(including_path)
      candidates = @scala_paths.select { |path| configured_base_for(path) == including_base }
      candidates = @scala_paths if candidates.empty?

      # Hoisted out of the loop: an interpolated regex literal recompiles
      # (PCRE2 JIT) on every evaluation, i.e. once per candidate file.
      class_decl_regex = /\b(?:class|object|trait)\s+#{Regex.escape(class_name)}\b/

      candidates.each do |path|
        next unless File.basename(path) == filename
        content = read_file_content(path)
        next unless content.match(class_decl_regex)
        next unless content.includes?("SimpleRouter") ||
                    content.includes?("Router.from") ||
                    content.includes?("routing.sird") ||
                    content.match(/extends\s+[\w.]*Router\b/)
        return {path: path, content: content, class_name: class_name}
      end

      nil
    end

    # Emit endpoints for a SIRD router's `routes` PartialFunction.
    private def process_sird_router(router : NamedTuple(path: String, content: String, class_name: String), prefix : String)
      source = router[:content]
      structure = blank_non_code(source)
      block = extract_router_routes_block(structure, source)
      return unless block

      body = block[:body]
      body_start = block[:start]

      # Each case maps an HTTP method + SIRD path pattern to a controller
      # action, e.g. `case GET(p"/$id") => controller.show(id)`.
      body.scan(/case\s+(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*p"([^"]*)"/) do |match|
        method = match[1]
        url_path, params = normalize_sird_path(match[2])
        full_path = join_paths(prefix, url_path)
        full_path = "/" if full_path.empty?

        line = line_at(source, body_start + (match.begin(0) || 0))
        endpoint = create_endpoint(full_path, method, router[:path], line)
        params.each do |param_name|
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
        @result << endpoint
      end
    end

    # Locate the brace block of a router's `routes` member.
    private def extract_router_routes_block(structure : String, source : String) : NamedTuple(body: String, start: Int32)?
      match = structure.match(/(?:override\s+)?(?:def|val|lazy\s+val)\s+routes\b/)
      return unless match
      search_from = match.end(0)
      return unless search_from

      open_brace = structure.index('{', search_from)
      return unless open_brace
      close = matching_brace(structure, open_brace)
      return unless close

      {body: source[(open_brace + 1)...close], start: open_brace + 1}
    end

    # Convert a SIRD `p"..."` path pattern to a `:param` URL and collect its
    # path params. Handles `$name`, `${name}` and `$name<regex>` interpolations.
    private def normalize_sird_path(pattern : String) : Tuple(String, Array(String))
      params = [] of String
      url = pattern.gsub(/\$\{(\w+)\}|\$(\w+)(?:<[^>]*>)?/) do |_|
        name = $~[1]? || $~[2]?
        if name
          params << name
          ":#{name}"
        else
          $~[0]
        end
      end
      url = "/#{url}" unless url.starts_with?("/")
      {url, params}
    end

    # Create an endpoint with the given path and method
    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param

      Endpoint.new(path, method, params, details)
    end
  end
end
