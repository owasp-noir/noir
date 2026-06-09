require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/java_parameter_extractor_ts"
require "../../../miniparsers/java_route_extractor_ts"

module Analyzer::Java
  class Armeria < Analyzer
    REGEX_SERVER_CODE_BLOCK = /Server\s*\.builder\(\s*\)\s*\.[^;]*build\(\)\s*\./
    alias RouteEntry = Tuple(String, String)
    alias ScopedClassKey = Tuple(String, String)

    # HTTP method annotation names supported by Armeria's annotated
    # service style. Simple names — fully-qualified forms like
    # `@com.linecorp.armeria.server.annotation.Get` are normalised to
    # the last segment before lookup.
    HTTP_METHOD_ANNOTATIONS = ["Get", "Post", "Put", "Delete", "Patch", "Head", "Options", "Trace"]
    PATH_ANNOTATION         = "Path"
    PATH_PREFIX_ANNOTATION  = "PathPrefix"

    def analyze
      # Source Analysis
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      annotated_service_prefixes = collect_annotated_service_prefixes
      service_with_routes_index = collect_service_with_routes_index

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
                  next if JavaEngine.test_path?(path)

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    content = read_file_content(path)
                    base = configured_base_for(path)

                    # Annotation-based services (`@Get("/x")` etc.) —
                    # Kotlin files reach here too, but tree-sitter-java
                    # doesn't parse Kotlin cleanly, so skip non-Java.
                    if content.includes?("com.linecorp.armeria.server.annotation.") && path.ends_with?(".java")
                      analyze_annotated_service(path, content, base, annotated_service_prefixes)
                    end

                    # Server.builder()-style routes (regex-scoped — the
                    # builder chain isn't worth a dedicated TS walk yet).
                    details = Details.new(PathInfo.new(path))
                    # Both the string-constant table (a full tree-sitter
                    # parse) and the non-code mask (a char walk) are only
                    # needed once a `Server.builder()...build()` chain is
                    # actually present. Most files are annotated services
                    # with no builder chain at all, so build both lazily
                    # on the first match to avoid parsing every file twice.
                    #
                    # The mask marks char offsets inside string literals or
                    # comments, letting us drop builder chains that only
                    # appear in documentation (e.g. a Kotlin `@Description`
                    # value or a Java text block) — a real FP source.
                    non_code_mask = nil.as(Array(Bool)?)
                    constants = nil.as(Hash(String, String)?)
                    content.scan(REGEX_SERVER_CODE_BLOCK) do |server_codeblock_match|
                      start = server_codeblock_match.begin(0)
                      if start
                        mask = (non_code_mask ||= build_non_code_mask(content))
                        next if start < mask.size && mask[start]
                      end
                      server_codeblock = server_codeblock_match[0]

                      resolved_constants = constants ||= (path.ends_with?(".java") ? Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content) : Hash(String, String).new)
                      collect_service_routes(server_codeblock, resolved_constants, details, service_with_routes_index, base)
                      collect_builder_routes(server_codeblock, resolved_constants, details)
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

      @result
    end

    ROUTE_VERB_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "trace"   => "TRACE",
    }

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile) — precompile the fixed per-verb call
    # matchers once at load time instead of per route expression.
    ROUTE_VERB_CALL_PATTERNS = ROUTE_VERB_METHODS.map do |method_name, http_method|
      {method_name, http_method, /\.\s*#{method_name}\s*\(([^)]*)\)/m}
    end

    private def collect_builder_routes(server_codeblock : String,
                                       constants : Hash(String, String),
                                       details : Details)
      emitted = Set(Tuple(String, String)).new

      route_chain_expressions(server_codeblock).each do |expr|
        collect_route_expression(expr, constants, details, emitted)
      end

      call_argument_expressions(server_codeblock, ".withRoute").each do |expr|
        collect_route_expression(expr, constants, details, emitted)
      end
    end

    private def collect_route_expression(expr : String,
                                         constants : Hash(String, String),
                                         details : Details,
                                         emitted : Set(Tuple(String, String)))
      route_entries_from_expression(expr, constants).each do |entry|
        emit_builder_route(entry[0], entry[1], details, emitted)
      end
    end

    private def route_entries_from_expression(expr : String,
                                              constants : Hash(String, String)) : Array(RouteEntry)
      routes = [] of RouteEntry
      direct_routes = [] of RouteEntry
      ROUTE_VERB_CALL_PATTERNS.each do |method_name, http_method, verb_call_regex|
        next unless expr.includes?(method_name)
        expr.scan(verb_call_regex) do |match|
          if path = first_builder_path_arg(match[1], constants)
            direct_routes << {http_method, path}
          end
        end
      end

      unless direct_routes.empty?
        routes.concat(direct_routes)
        return routes
      end

      paths = route_builder_paths(expr, constants)
      return routes if paths.empty?

      methods = route_builder_methods(expr)
      methods = ["ANY"] if methods.empty?

      methods.each do |method|
        paths.each do |path|
          routes << {method, path}
        end
      end
      routes
    end

    private def emit_builder_route(method : String,
                                   path : String,
                                   details : Details,
                                   emitted : Set(Tuple(String, String)))
      return unless path.starts_with?("/")
      key = {method, path}
      return if emitted.includes?(key)

      emitted << key
      @result << Endpoint.new(path, method, details)
    end

    private def route_chain_expressions(code : String) : Array(String)
      expressions = [] of String
      offset = 0

      while found = code.index(".route()", offset)
        build_idx = code.index(".build", found)
        break unless build_idx
        open_idx = code.index('(', build_idx)
        break unless open_idx
        close_idx = find_matching_delimiter(code, open_idx, '(', ')')
        if close_idx
          expressions << code[found..close_idx]
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end

      expressions
    end

    private def call_argument_expressions(code : String, marker : String) : Array(String)
      expressions = [] of String
      offset = 0

      while found = code.index(marker, offset)
        open_idx = code.index('(', found)
        break unless open_idx
        close_idx = find_matching_delimiter(code, open_idx, '(', ')')
        if close_idx
          expressions << code[(open_idx + 1)...close_idx]
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end

      expressions
    end

    private def route_builder_paths(expr : String, constants : Hash(String, String)) : Array(String)
      paths = [] of String
      expr.scan(/\.\s*(?:path|exact|prefix|glob)\s*\(([^)]*)\)/m) do |match|
        if path = first_builder_path_arg(match[1], constants)
          paths << path
        end
      end
      paths.uniq
    end

    private def route_builder_methods(expr : String) : Array(String)
      methods = [] of String
      expr.scan(/\.\s*methods?\s*\(([^)]*)\)/m) do |match|
        match[1].scan(/(?:HttpMethod\.)?([A-Z]+)/) do |method_match|
          method = method_match[1].upcase
          methods << method if HTTP_METHOD_NAMES.includes?(method)
        end
      end
      methods.uniq
    end

    HTTP_METHOD_NAMES = Set{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"}

    private def collect_service_routes(server_codeblock : String,
                                       constants : Hash(String, String),
                                       details : Details,
                                       service_with_routes_index : Hash(ScopedClassKey, Array(RouteEntry)),
                                       base : String)
      emitted = Set(Tuple(String, String)).new
      offset = 0
      while found = server_codeblock.index(".service", offset)
        offset = found + 8
        suffix = server_codeblock[found..]
        method_name =
          if suffix.starts_with?(".serviceIf")
            "serviceIf"
          elsif suffix.starts_with?(".serviceUnder")
            "serviceUnder"
          elsif suffix.starts_with?(".service")
            "service"
          else
            next
          end
        endpoint_param_index = method_name == "serviceIf" ? 1 : 0

        open_idx = server_codeblock.index('(', found)
        next unless open_idx
        close_idx = find_matching_delimiter(server_codeblock, open_idx, '(', ')')
        next unless close_idx

        args = split_top_level_args(server_codeblock[(open_idx + 1)...close_idx])
        next unless args.size > endpoint_param_index

        endpoint_expr = args[endpoint_param_index]
        service_arg = args[endpoint_param_index + 1]? || ""
        service_lookup_expr = service_arg.empty? ? endpoint_expr : service_arg

        route_argument_entries = route_entries_from_expression(endpoint_expr, constants)
        unless route_argument_entries.empty?
          route_argument_entries.each do |entry|
            emit_builder_route(entry[0], entry[1], details, emitted)
          end
          next
        end

        endpoint = first_builder_path_arg(endpoint_expr, constants) || ""
        service_routes = indexed_service_routes(service_lookup_expr, service_with_routes_index, base)

        if !service_routes.empty? && (method_name == "service" || method_name == "serviceUnder")
          base_path = method_name == "serviceUnder" ? endpoint : ""
          service_routes.each do |entry|
            emit_builder_route(entry[0], join_paths(base_path, entry[1]), details, emitted)
          end
          next
        end

        next unless endpoint.starts_with?("/")

        if file_service_expression?(service_arg)
          @result << Endpoint.new(endpoint, "GET", details)
          @result << Endpoint.new(endpoint, "HEAD", details)
        else
          @result << Endpoint.new(endpoint, "ANY", details)
        end
      end
    end

    private def indexed_service_routes(service_arg : String,
                                       service_with_routes_index : Hash(ScopedClassKey, Array(RouteEntry)),
                                       base : String) : Array(RouteEntry)
      service_class = service_class_name(service_arg)
      return [] of RouteEntry unless service_class

      service_with_routes_index[{base, service_class}]? || [] of RouteEntry
    end

    private def file_service_expression?(expr : String) : Bool
      expr.includes?("FileService.") ||
        expr.includes?("HttpFile.") ||
        expr.includes?(".asService()")
    end

    private def first_builder_path_arg(args : String, constants : Hash(String, String)) : String?
      resolve_builder_path_expression(args, constants)
    end

    private def resolve_builder_path_expression(expr : String,
                                                constants : Hash(String, String),
                                                depth = 0) : String?
      return if depth > 16

      expression = strip_wrapping_parentheses(expr.strip)
      return if expression.empty?

      if expression.starts_with?('"') && expression.ends_with?('"')
        return decode_raw_string(expression)
      end

      if expression.includes?("+")
        parts = split_top_level_concat(expression)
        return if parts.empty?
        values = parts.compact_map { |part| resolve_builder_path_expression(part, constants, depth + 1) }
        return unless values.size == parts.size
        return values.join
      end

      if identifier = expression.match(/\A[A-Za-z_][A-Za-z0-9_.]*\z/)
        return resolve_builder_constant(identifier[0], constants)
      end

      nil
    end

    private def resolve_builder_constant(name : String, constants : Hash(String, String)) : String?
      if value = constants[name]?
        return value
      end

      suffix = ".#{name}"
      matches = constants.compact_map do |key, resolved|
        key.ends_with?(suffix) ? resolved : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def split_top_level_concat(expr : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      expr.each_char_with_index do |char, index|
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
        when '+'
          next unless depth == 0

          parts << expr[start...index].strip
          start = index + 1
        end
      end

      tail = expr[start..]?.to_s.strip
      parts << tail unless tail.empty?
      parts
    end

    private def strip_wrapping_parentheses(expr : String) : String
      result = expr
      while result.starts_with?('(') && result.ends_with?(')')
        close_idx = find_matching_delimiter(result, 0, '(', ')')
        break unless close_idx == result.size - 1
        result = result[1...-1].strip
      end
      result
    end

    private def decode_raw_string(raw : String) : String
      return raw unless raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"')
      raw[1...-1].gsub(/\\(["\\])/, "\\1")
    end

    private def collect_annotated_service_prefixes : Hash(ScopedClassKey, Array(String))
      registrations = Hash(ScopedClassKey, Array(String)).new { |hash, key| hash[key] = [] of String }

      get_files_by_extension(".java").each do |path|
        next if JavaEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?(".annotatedService")

        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content)
        base = configured_base_for(path)
        call_argument_expressions(content, ".annotatedService").each do |expr|
          prefix, service_class = annotated_service_registration(expr, constants)
          next if service_class.empty?

          registrations[{base, service_class}] << prefix
        end
      rescue File::NotFoundError
        logger.debug "File not found: #{path}"
      end

      registrations.each_value(&.uniq!)
      registrations
    end

    private def collect_service_with_routes_index : Hash(ScopedClassKey, Array(RouteEntry))
      index = Hash(ScopedClassKey, Array(RouteEntry)).new

      get_files_by_extension(".java").each do |path|
        next if JavaEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?("HttpServiceWithRoutes") || content.includes?("ServiceWithRoutes")

        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content)
        base = configured_base_for(path)
        Noir::TreeSitter.parse_java(content) do |root|
          walk_class_containers(root) do |cls|
            next unless service_with_routes_class?(cls, content)

            class_name = class_name_of(cls, content)
            next if class_name.empty?

            routes = service_with_routes_entries(cls, content, constants)
            index[{base, class_name}] = routes unless routes.empty?
          end
        end
      rescue File::NotFoundError
        logger.debug "File not found: #{path}"
      end

      index
    end

    private def service_with_routes_class?(cls : LibTreeSitter::TSNode, content : String) : Bool
      header = Noir::TreeSitter.node_text(cls, content)
      # Bound the header at the class body via the AST, not the first '{' — an
      # annotation arg like `@SomeAnno({"a","b"})` would otherwise truncate the
      # `implements HttpServiceWithRoutes` clause and drop the class's routes.
      if body = Noir::TreeSitter.field(cls, "body")
        class_start = LibTreeSitter.ts_node_start_byte(cls).to_i
        body_start = LibTreeSitter.ts_node_start_byte(body).to_i
        header = content.byte_slice(class_start, body_start - class_start)
      end

      header.includes?("HttpServiceWithRoutes") || header.includes?("ServiceWithRoutes")
    end

    private def service_with_routes_entries(cls : LibTreeSitter::TSNode,
                                            content : String,
                                            constants : Hash(String, String)) : Array(RouteEntry)
      routes = [] of RouteEntry
      body = Noir::TreeSitter.field(cls, "body")
      return routes unless body

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        name = Noir::TreeSitter.field(member, "name")
        next unless name && Noir::TreeSitter.node_text(name, content) == "routes"

        method_body = Noir::TreeSitter.field(member, "body")
        next unless method_body
        route_builder_expressions(Noir::TreeSitter.node_text(method_body, content)).each do |expr|
          routes.concat(route_entries_from_expression(expr, constants))
        end
      end

      routes.uniq
    end

    private def route_builder_expressions(code : String) : Array(String)
      expressions = [] of String
      offset = 0

      while found = code.index("Route.builder()", offset)
        build_idx = code.index(".build", found + "Route.builder()".size)
        break unless build_idx
        open_idx = code.index('(', build_idx)
        break unless open_idx
        close_idx = find_matching_delimiter(code, open_idx, '(', ')')
        if close_idx
          expressions << code[found..close_idx]
          offset = close_idx + 1
        else
          offset = open_idx + 1
        end
      end

      expressions
    end

    private def annotated_service_registration(expr : String,
                                               constants : Hash(String, String)) : Tuple(String, String)
      args = split_top_level_args(expr)
      return {"", ""} if args.empty?

      if args.size == 1
        return {"", service_class_name(args[0]) || ""}
      end

      prefix = first_builder_path_arg(args[0], constants) || ""
      {prefix, service_class_name(args[1]) || ""}
    end

    private def service_class_name(expr : String) : String?
      if match = expr.match(/\bnew\s+([A-Za-z_][A-Za-z0-9_.$]*)\s*\(/)
        return simple_class_name(match[1])
      end

      if match = expr.match(/\b([A-Za-z_][A-Za-z0-9_.$]*)\s*\.class\b/)
        return simple_class_name(match[1])
      end

      nil
    end

    private def simple_class_name(name : String) : String
      name.split(/[.$]/).last
    end

    private def split_top_level_args(expr : String) : Array(String)
      args = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      expr.each_char_with_index do |char, index|
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

          args << expr[start...index].strip
          start = index + 1
        end
      end

      tail = expr[start..]?.to_s.strip
      args << tail unless tail.empty?
      args
    end

    # Marks character offsets that fall inside a string literal or a
    # comment. Used to reject `Server.builder()...build()` chains that
    # only appear inside documentation — e.g. an `@Description` value or
    # a Java text block / Kotlin raw string showing example code. Handles
    # `//` line comments, `/* */` block comments, triple-quoted strings,
    # double-quoted strings and char literals (with `\` escapes).
    private def build_non_code_mask(content : String) : Array(Bool)
      chars = content.chars
      n = chars.size
      mask = Array(Bool).new(n, false)
      i = 0
      while i < n
        c = chars[i]
        nxt = i + 1 < n ? chars[i + 1] : '\0'

        if c == '/' && nxt == '/'
          while i < n && chars[i] != '\n'
            mask[i] = true
            i += 1
          end
          next
        end

        if c == '/' && nxt == '*'
          mask[i] = true
          mask[i + 1] = true
          i += 2
          while i < n
            if chars[i] == '*' && i + 1 < n && chars[i + 1] == '/'
              mask[i] = true
              mask[i + 1] = true
              i += 2
              break
            end
            mask[i] = true
            i += 1
          end
          next
        end

        if c == '"' && nxt == '"' && i + 2 < n && chars[i + 2] == '"'
          mask[i] = mask[i + 1] = mask[i + 2] = true
          i += 3
          while i < n
            if chars[i] == '"' && i + 2 < n && chars[i + 1] == '"' && chars[i + 2] == '"'
              mask[i] = mask[i + 1] = mask[i + 2] = true
              i += 3
              break
            end
            mask[i] = true
            i += 1
          end
          next
        end

        if c == '"' || c == '\''
          mask[i] = true
          i += 1
          while i < n
            ch = chars[i]
            if ch == '\\'
              mask[i] = true
              mask[i + 1] = true if i + 1 < n
              i += 2
              next
            end
            mask[i] = true
            i += 1
            break if ch == c
          end
          next
        end

        i += 1
      end
      mask
    end

    private def find_matching_delimiter(code : String,
                                        open_idx : Int32,
                                        open_char : Char,
                                        close_char : Char) : Int32?
      # Scan by CHARACTER (not byte): open_idx is a char index from String#index
      # and callers char-slice with the returned index. A byte scan corrupts both
      # on multi-byte UTF-8. ASCII-identical to the previous byte loop.
      depth = 1
      in_string = false
      quote = '\0'
      escape = false

      code.each_char_with_index do |ch, i|
        next if i <= open_idx
        if in_string
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == quote
            in_string = false
          end
        else
          if ch == '"' || ch == '\''
            in_string = true
            quote = ch
          elsif ch == open_char
            depth += 1
          elsif ch == close_char
            depth -= 1
          end
        end
        return i if depth == 0
      end

      nil
    end

    # ---- annotation-based service routes ------------------------------

    private def analyze_annotated_service(path : String,
                                          content : String,
                                          base : String,
                                          annotated_service_prefixes : Hash(ScopedClassKey, Array(String)))
      Noir::TreeSitter.parse_java(content) do |root|
        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
        dto_index = Noir::TreeSitterJavaDtoIndex.new.build_for_with_root(path, content, root)
        walk_class_containers(root) do |cls|
          class_name = class_name_of(cls, content)
          prefixes = annotated_service_route_prefixes(
            class_name,
            base,
            annotation_values_named(cls, PATH_PREFIX_ANNOTATION, content, constants, class_name),
            annotated_service_prefixes
          )

          cls_body = Noir::TreeSitter.field(cls, "body")
          next unless cls_body
          Noir::TreeSitter.each_named_child(cls_body) do |member|
            next unless Noir::TreeSitter.node_type(member) == "method_declaration"
            handle_method(member, content, path, prefixes, constants, class_name, dto_index)
          end
        end
      end
    end

    private def annotated_service_route_prefixes(class_name : String,
                                                 base : String,
                                                 class_prefixes : Array(String),
                                                 annotated_service_prefixes : Hash(ScopedClassKey, Array(String))) : Array(String)
      registration_prefixes = annotated_service_prefixes[{base, class_name}]? || [] of String
      registration_prefixes = [""] if registration_prefixes.empty?
      class_prefixes = [""] if class_prefixes.empty?

      prefixes = [] of String
      registration_prefixes.each do |registration_prefix|
        class_prefixes.each do |class_prefix|
          prefixes << join_paths(registration_prefix, class_prefix)
        end
      end
      prefixes.uniq
    end

    private def walk_class_containers(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      ty = Noir::TreeSitter.node_type(node)
      if ty == "class_declaration" || ty == "interface_declaration"
        block.call(node)
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_class_containers(child, &block)
      end
    end

    private def class_name_of(class_decl : LibTreeSitter::TSNode, content : String) : String
      name = Noir::TreeSitter.field(class_decl, "name")
      name ? Noir::TreeSitter.node_text(name, content) : ""
    end

    private def handle_method(method : LibTreeSitter::TSNode,
                              content : String,
                              path : String,
                              prefixes : Array(String),
                              constants : Hash(String, String),
                              current_class : String,
                              dto_index : Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)))
      mods = find_modifiers(method)
      return unless mods

      explicit_paths = [] of String
      http_annotations = [] of Tuple(String, Array(String), LibTreeSitter::TSNode)

      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        name_node = Noir::TreeSitter.field(ann, "name")
        next unless name_node
        ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name_node, content))

        if HTTP_METHOD_ANNOTATIONS.includes?(ann_name)
          http_annotations << {ann_name, annotation_values(ann, ann_name, content, constants, current_class), ann}
        elsif ann_name == PATH_ANNOTATION
          explicit_paths.concat(annotation_values(ann, ann_name, content, constants, current_class))
        end
      end

      http_annotations.each do |entry|
        ann_name, annotation_paths, ann = entry
        route_paths = annotation_paths.empty? ? explicit_paths : annotation_paths
        next if route_paths.empty?
        http_method = ann_name.upcase
        line = Noir::TreeSitter.node_start_row(ann) + 1
        details = Details.new(PathInfo.new(path, line))

        prefixes.each do |prefix|
          route_paths.each do |route_path|
            url_path = join_paths(prefix, route_path)
            parameters = collect_method_params(method, content, url_path, constants, current_class, dto_index)
            endpoint = Endpoint.new(url_path, http_method, parameters, details)
            collect_method_callees(method, content, path).each do |(name, callee_path, callee_line)|
              endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
            end
            extract_path_parameters(url_path, endpoint)
            @result << endpoint
          end
        end
      end
    end

    private def collect_method_callees(method : LibTreeSitter::TSNode,
                                       content : String,
                                       path : String) : Array(Tuple(String, String, Int32))
      return [] of Tuple(String, String, Int32) unless any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      body = Noir::TreeSitter.field(method, "body")
      return [] of Tuple(String, String, Int32) unless body

      Noir::JavaCalleeExtractor.callees_in_body(body, content, path)
    end

    private def find_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_annotation_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    private def annotation_values(ann : LibTreeSitter::TSNode,
                                  ann_name : String,
                                  content : String,
                                  constants : Hash(String, String),
                                  current_class : String = "") : Array(String)
      args = Noir::TreeSitter.field(ann, "arguments")
      return [] of String unless args
      result = [] of String
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
          collect_string_values(arg, content, constants, result, current_class)
        when "array_initializer", "element_value_array_initializer"
          collect_string_values(arg, content, constants, result, current_class)
        when "element_value_pair"
          key = Noir::TreeSitter.field(arg, "key")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          key_name = Noir::TreeSitter.node_text(key, content)
          next unless annotation_value_key?(ann_name, key_name)
          collect_string_values(val, content, constants, result, current_class)
        end
      end
      result
    end

    private def annotation_values_named(decl : LibTreeSitter::TSNode,
                                        target_name : String,
                                        content : String,
                                        constants : Hash(String, String),
                                        current_class : String = "") : Array(String)
      values = [] of String
      mods = find_modifiers(decl)
      return values unless mods

      Noir::TreeSitter.each_named_child(mods) do |ann|
        ty = Noir::TreeSitter.node_type(ann)
        next unless ty == "annotation" || ty == "marker_annotation"
        name_node = Noir::TreeSitter.field(ann, "name")
        next unless name_node
        ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name_node, content))
        next unless ann_name == target_name
        values.concat(annotation_values(ann, ann_name, content, constants, current_class))
      end

      values
    end

    private def annotation_value_key?(ann_name : String, key_name : String) : Bool
      return key_name == "value" || key_name == "name" if ann_name == "Param" || ann_name == "Header"

      key_name == "value" || key_name == "path"
    end

    private def collect_string_values(node : LibTreeSitter::TSNode,
                                      content : String,
                                      constants : Hash(String, String),
                                      sink : Array(String),
                                      current_class : String = "")
      case Noir::TreeSitter.node_type(node)
      when "array_initializer", "element_value_array_initializer"
        Noir::TreeSitter.each_named_child(node) do |child|
          collect_string_values(child, content, constants, sink, current_class)
        end
      else
        if resolved = resolve_string_value(node, content, constants, current_class)
          sink << resolved
        end
      end
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     content : String,
                                     constants : Hash(String, String),
                                     current_class : String = "",
                                     depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, content)
      when "identifier", "field_access", "scoped_identifier"
        resolve_constant_reference(Noir::TreeSitter.node_text(node, content), constants, current_class)
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, content).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_value = resolve_string_value(left, content, constants, current_class, depth + 1)
        right_value = resolve_string_value(right, content, constants, current_class, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_string_value(child, content, constants, current_class, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String,
                                           constants : Hash(String, String),
                                           current_class : String = "") : String?
      unless current_class.empty?
        if resolved = constants["#{current_class}.#{name}"]?
          return resolved
        end
      end

      if resolved = constants[name]?
        return resolved
      end

      suffix = ".#{name}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    # Walk method formal_parameters, translating Armeria's annotation
    # set into `Param`s:
    #
    #   - `@Param("name")` — query parameter (unless the name matches a
    #     `{template}` variable in the URL, in which case it's a path
    #     parameter and surfaces later through `extract_path_parameters`)
    #   - `@Header("Name")` — header parameter
    #   - `@RequestObject` — JSON body; DTO fields are expanded when
    #     visible through the Java import graph, otherwise the declared
    #     variable name is emitted as a fallback.
    private def collect_method_params(method : LibTreeSitter::TSNode,
                                      content : String,
                                      url_path : String,
                                      constants : Hash(String, String),
                                      current_class : String,
                                      dto_index : Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo))) : Array(Param)
      params = [] of Param
      fparams = Noir::TreeSitter.field(method, "parameters")
      return params unless fparams

      path_param_names = Set(String).new
      # `\*?` also matches Armeria's rest-path capture `{*name}` so a
      # matching `@Param name` is recognised as a path variable rather
      # than emitted as a spurious query parameter.
      url_path.scan(/\{\*?(\w+)\}/) do |match|
        path_param_names << match[1] if match.size > 1
      end

      Noir::TreeSitter.each_named_child(fparams) do |fp|
        next unless Noir::TreeSitter.node_type(fp) == "formal_parameter"
        name_node = Noir::TreeSitter.field(fp, "name")
        next unless name_node
        arg_name = Noir::TreeSitter.node_text(name_node, content)
        type_name = formal_parameter_type(fp, content)

        param_mods = find_modifiers(fp)
        next unless param_mods

        default_value = ""
        Noir::TreeSitter.each_named_child(param_mods) do |pa|
          pa_ty = Noir::TreeSitter.node_type(pa)
          next unless pa_ty == "annotation" || pa_ty == "marker_annotation"
          name = Noir::TreeSitter.field(pa, "name")
          next unless name
          ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name, content))
          next unless ann_name == "Default"
          default_value = extract_annotation_string_arg(pa, content, constants, current_class) || ""
          break
        end

        Noir::TreeSitter.each_named_child(param_mods) do |pa|
          pa_ty = Noir::TreeSitter.node_type(pa)
          next unless pa_ty == "annotation" || pa_ty == "marker_annotation"
          name = Noir::TreeSitter.field(pa, "name")
          next unless name
          ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name, content))

          case ann_name
          when "Param"
            param_name = extract_annotation_string_arg(pa, content, constants, current_class) || arg_name
            # Path params are emitted later by `extract_path_parameters`;
            # skip here to avoid duplicates.
            next if path_param_names.includes?(param_name)
            params << Param.new(param_name, default_value, "query")
          when "Header"
            param_name = extract_annotation_string_arg(pa, content, constants, current_class) || arg_name
            params << Param.new(param_name, default_value, "header")
          when "RequestObject"
            emit_request_object_params(type_name, arg_name, dto_index, params)
          end
        end
      end

      params
    end

    private def emit_request_object_params(type_name : String,
                                           arg_name : String,
                                           dto_index : Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)),
                                           sink : Array(Param))
      fields = dto_index[type_name]?
      emitted = false

      if fields
        fields.each do |field|
          next unless field.access_modifier == "public" || field.has_setter?

          sink << Param.new(field.name, field.init_value, "json")
          emitted = true
        end
      end

      sink << Param.new(arg_name, "", "json") unless emitted
    end

    private def formal_parameter_type(param : LibTreeSitter::TSNode, content : String) : String
      Noir::TreeSitter.each_named_child(param) do |child|
        case Noir::TreeSitter.node_type(child)
        when "type_identifier", "integral_type", "floating_point_type", "boolean_type", "void_type"
          return Noir::TreeSitter.node_text(child, content)
        when "generic_type", "scoped_type_identifier", "array_type"
          type_name = leaf_type_name(child, content)
          return type_name unless type_name.empty?
        end
      end
      ""
    end

    private def leaf_type_name(node : LibTreeSitter::TSNode, content : String) : String
      ty = Noir::TreeSitter.node_type(node)
      return Noir::TreeSitter.node_text(node, content) if ty == "type_identifier"

      Noir::TreeSitter.each_named_child(node) do |child|
        leaf = leaf_type_name(child, content)
        return leaf unless leaf.empty?
      end
      ""
    end

    private def extract_annotation_string_arg(ann : LibTreeSitter::TSNode,
                                              content : String,
                                              constants : Hash(String, String),
                                              current_class : String) : String?
      name_node = Noir::TreeSitter.field(ann, "name")
      return unless name_node
      ann_name = simple_annotation_name(Noir::TreeSitter.node_text(name_node, content))
      annotation_values(ann, ann_name, content, constants, current_class).first?
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, content : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, content)
          end
        end
      end
      buf
    end

    # Extract path parameters from URLs like /users/{userId} or /items/{itemId}/comments
    # (`\*?` also captures the rest-path form `{*name}` as `name`).
    private def extract_path_parameters(url : String, endpoint : Endpoint)
      url.scan(/\{\*?(\w+)\}/) do |match|
        if match.size > 0
          param_name = match[1]
          # Only add if not already present
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end

      url.scan(/:(\w+)/) do |match|
        next unless match.size > 0
        param_name = match[1]
        unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          endpoint.push_param(Param.new(param_name, "", "path"))
        end
      end
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
