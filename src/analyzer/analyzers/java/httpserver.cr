require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/java_route_extractor_ts"

module Analyzer::Java
  # JDK built-in HTTP server (`com.sun.net.httpserver.HttpServer`,
  # `jdk.httpserver` module, available since Java 6). Routes are
  # registered with `server.createContext("/path", handler)`, where the
  # handler is a lambda, an `HttpHandler` instance/anonymous class, or a
  # method reference.
  #
  # Unlike declarative frameworks the HTTP verb is *not* bound at
  # registration — handlers branch on `exchange.getRequestMethod()` — so
  # this analyzer recovers the path from the `createContext` call and the
  # verb(s)/params from the resolved handler body. When the handler is a
  # named/anonymous `HttpHandler`, its `handle(...)` body is resolved
  # within the same file (cross-file handler classes are out of scope,
  # mirroring the other JVM extractors).
  #
  # Reference: https://docs.oracle.com/en/java/javase/21/docs/api/jdk.httpserver/com/sun/net/httpserver/HttpServer.html
  class HttpServer < Analyzer
    JAVA_EXTENSION = "java"
    PACKAGE_MARKER = "com.sun.net.httpserver"
    CREATE_CONTEXT = "createContext"
    HANDLE_METHOD  = "handle"
    HTTP_METHODS   = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"]
    # Verbs that carry a request body — the body param is attached only
    # to these so a method-dispatching handler doesn't surface a body on
    # its GET branch.
    BODY_VERBS = ["POST", "PUT", "PATCH", "DELETE"]

    # `getRequestMethod()` verb comparisons. Hoisted as constants because
    # interpolated regexes recompile on every evaluation.
    RE_GRM_EQUALS     = /getRequestMethod\s*\(\s*\)\s*\.\s*equals(?:IgnoreCase)?\s*\(\s*"([A-Za-z]+)"/
    RE_GRM_EQ         = /getRequestMethod\s*\(\s*\)\s*==\s*"([A-Za-z]+)"/
    RE_EQUALS_GRM     = /"([A-Za-z]+)"\s*\.\s*equals(?:IgnoreCase)?\s*\(\s*[A-Za-z0-9_.\s]*getRequestMethod\s*\(\s*\)\s*\)/
    RE_EQ_GRM         = /"([A-Za-z]+)"\s*==\s*[A-Za-z0-9_.\s]*getRequestMethod\s*\(\s*\)/
    RE_GRM_VAR_ASSIGN = /\b([A-Za-z_]\w*)\s*=\s*[^;=][^;]*getRequestMethod\s*\(\s*\)/
    # A `case` label group: one or more verb literals (Java allows
    # `case "GET", "HEAD":`) terminated by a colon or an arrow (Java 14+
    # `case "GET" -> ...`).
    RE_CASE_GROUP   = /\bcase\s+("[A-Za-z]+"(?:\s*,\s*"[A-Za-z]+")*)\s*(?:->|:)/
    RE_VERB_LITERAL = /"([A-Za-z]+)"/
    SWITCH_KEYWORD  = "switch"

    RE_HEADER = /getRequestHeaders\s*\(\s*\)\s*\.\s*(?:getFirst|get)\s*\(\s*"([^"]+)"/
    RE_BODY   = /getRequestBody\s*\(\s*\)/

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next if JavaEngine.test_path?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next unless File.exists?(path)

        content = read_file_content(path)
        next unless content.includes?(PACKAGE_MARKER)
        next unless content.includes?(CREATE_CONTEXT)

        analyze_file(content, path, include_callee)
      end

      Fiber.yield
      @result
    end

    private def analyze_file(content : String, path : String, include_callee : Bool)
      Noir::TreeSitter.parse_java(content) do |root|
        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
        # Same-file declaration indexes for resolving named-handler
        # classes (`new MyHandler()`) and method references (`App::handle`).
        class_index = {} of String => LibTreeSitter::TSNode
        method_index = {} of String => LibTreeSitter::TSNode
        walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "class_declaration"  then index_decl(node, content, class_index)
          when "method_declaration" then index_decl(node, content, method_index)
          end
        end

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "method_invocation"
          name_node = Noir::TreeSitter.field(node, "name")
          next unless name_node
          next unless Noir::TreeSitter.node_text(name_node, content) == CREATE_CONTEXT

          handle_create_context(node, content, path, constants, class_index, method_index, include_callee)
        end
      end
    rescue e
      logger.debug "java httpserver: failed to analyze #{path}: #{e.message}"
    end

    private def handle_create_context(call : LibTreeSitter::TSNode,
                                      content : String,
                                      path : String,
                                      constants : Hash(String, String),
                                      class_index : Hash(String, LibTreeSitter::TSNode),
                                      method_index : Hash(String, LibTreeSitter::TSNode),
                                      include_callee : Bool)
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      arg_nodes = argument_nodes(args)
      path_arg = arg_nodes[0]?
      return unless path_arg

      route_path = resolve_string(path_arg, content, constants)
      return unless route_path
      # `createContext("")` is rejected by the JDK at runtime — don't let an
      # empty literal normalize into a phantom `/` route.
      return if route_path.strip.empty?
      route_path = normalize_path(route_path)
      return unless valid_path?(route_path)

      line = Noir::TreeSitter.node_start_row(call) + 1
      handler_arg = arg_nodes[1]?
      body = handler_arg ? resolve_handler_body(handler_arg, content, class_index, method_index) : nil

      methods = ["GET"]
      header_params = [] of String
      has_body = false
      callees = [] of Tuple(String, String, Int32)

      if body
        body_text = Noir::TreeSitter.node_text(body, content)
        detected = detect_methods(body_text)
        methods = detected unless detected.empty?
        header_params = detect_headers(body_text)
        has_body = body_text.matches?(RE_BODY)
        callees = Noir::JavaCalleeExtractor.callees_in_body(body, content, path) if include_callee
      end

      methods.each do |verb|
        params = [] of Param
        header_params.each { |name| params << Param.new(name, "", "header") }
        params << Param.new("body", "", "json") if has_body && BODY_VERBS.includes?(verb)

        endpoint = Endpoint.new(route_path, verb, params, Details.new(PathInfo.new(path, line)))
        callees.each do |entry|
          callee_name, callee_path, callee_line = entry
          endpoint.push_callee(Callee.new(callee_name, path: callee_path, line: callee_line))
        end
        @result << endpoint
      end
    end

    # ---- handler body resolution -------------------------------------

    private def resolve_handler_body(handler : LibTreeSitter::TSNode,
                                     content : String,
                                     class_index : Hash(String, LibTreeSitter::TSNode),
                                     method_index : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      case Noir::TreeSitter.node_type(handler)
      when "lambda_expression"
        Noir::TreeSitter.field(handler, "body")
      when "object_creation_expression"
        if class_body = anonymous_class_body(handler)
          # `new HttpHandler() { public void handle(...) { ... } }`
          method = find_method_in_body(class_body, content, HANDLE_METHOD)
          method ? Noir::TreeSitter.field(method, "body") : nil
        else
          # `new MyHandler()` — resolve the class in the same file.
          type_node = Noir::TreeSitter.field(handler, "type")
          return unless type_node
          class_name = simple_name(Noir::TreeSitter.node_text(type_node, content))
          class_node = class_index[class_name]?
          return unless class_node
          method = find_method_in_class(class_node, content, HANDLE_METHOD)
          method ? Noir::TreeSitter.field(method, "body") : nil
        end
      when "method_reference"
        # `App::handle`, `this::serve`, `ClassName::method`.
        method_name = Noir::TreeSitter.node_text(handler, content).split("::").last.strip
        method_node = method_index[method_name]?
        method_node ? Noir::TreeSitter.field(method_node, "body") : nil
      end
    end

    private def anonymous_class_body(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      result = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        result = child if Noir::TreeSitter.node_type(child) == "class_body"
      end
      result
    end

    private def find_method_in_class(class_node : LibTreeSitter::TSNode,
                                     content : String,
                                     name : String) : LibTreeSitter::TSNode?
      body = Noir::TreeSitter.field(class_node, "body")
      return unless body
      find_method_in_body(body, content, name)
    end

    private def find_method_in_body(body : LibTreeSitter::TSNode,
                                    content : String,
                                    name : String) : LibTreeSitter::TSNode?
      result = nil
      Noir::TreeSitter.each_named_child(body) do |child|
        next unless Noir::TreeSitter.node_type(child) == "method_declaration"
        name_node = Noir::TreeSitter.field(child, "name")
        next unless name_node
        result = child if Noir::TreeSitter.node_text(name_node, content) == name
      end
      result
    end

    # ---- verb / param detection --------------------------------------

    private def detect_methods(text : String) : Array(String)
      verbs = [] of String
      scan_into(text, RE_GRM_EQUALS, verbs)
      scan_into(text, RE_GRM_EQ, verbs)
      scan_into(text, RE_EQUALS_GRM, verbs)
      scan_into(text, RE_EQ_GRM, verbs)

      # `String method = exchange.getRequestMethod();` then later compared
      # against verb literals or switched on.
      method_vars = [] of String
      text.scan(RE_GRM_VAR_ASSIGN) do |m|
        method_vars << m[1] unless method_vars.includes?(m[1])
      end

      method_vars.each do |var|
        escaped = Regex.escape(var)
        scan_into(text, /\b#{escaped}\s*\.\s*equals(?:IgnoreCase)?\s*\(\s*"([A-Za-z]+)"/, verbs)
        scan_into(text, /\b#{escaped}\s*==\s*"([A-Za-z]+)"/, verbs)
        scan_into(text, /"([A-Za-z]+)"\s*\.\s*equals(?:IgnoreCase)?\s*\(\s*#{escaped}\s*\)/, verbs)
        scan_into(text, /"([A-Za-z]+)"\s*==\s*#{escaped}/, verbs)
      end

      collect_switch_verbs(text, method_vars, verbs)

      verbs.map(&.upcase).select { |verb| HTTP_METHODS.includes?(verb) }.uniq!
    end

    # Collect verb literals from the case labels of `switch` statements that
    # dispatch on the request method — `switch (exchange.getRequestMethod())`
    # or `switch (method)` for a variable bound to it (`.toUpperCase()` and
    # other chained calls in the selector are tolerated). Scanning is scoped
    # to each matching switch block (located with a string/comment-aware
    # delimiter matcher) so case labels from an unrelated string `switch` in
    # the same handler aren't mistaken for verbs.
    private def collect_switch_verbs(text : String, method_vars : Array(String), verbs : Array(String))
      return unless text.includes?(SWITCH_KEYWORD)

      chars = text.chars
      size = chars.size
      index = 0
      while index < size
        unless keyword_at?(chars, index, SWITCH_KEYWORD)
          index += 1
          next
        end

        selector_open = skip_whitespace(chars, index + SWITCH_KEYWORD.size)
        if selector_open < size && chars[selector_open] == '('
          selector_close = matching_delimiter(chars, selector_open)
          if selector_close
            selector = slice_chars(chars, selector_open + 1, selector_close)
            block_open = skip_whitespace(chars, selector_close + 1)
            if method_switch_selector?(selector, method_vars) &&
               block_open < size && chars[block_open] == '{'
              block_close = matching_delimiter(chars, block_open) || size
              block = slice_chars(chars, block_open + 1, block_close)
              block.scan(RE_CASE_GROUP) do |group|
                group[1].scan(RE_VERB_LITERAL) { |literal| verbs << literal[1] }
              end
            end
            index = selector_close + 1
            next
          end
        end
        index += 1
      end
    end

    private def method_switch_selector?(selector : String, method_vars : Array(String)) : Bool
      return true if selector.includes?("getRequestMethod")
      method_vars.includes?(selector.strip)
    end

    private def detect_headers(text : String) : Array(String)
      names = [] of String
      text.scan(RE_HEADER) do |m|
        names << m[1] unless names.includes?(m[1])
      end
      names
    end

    private def scan_into(text : String, regex : Regex, sink : Array(String))
      text.scan(regex) { |m| sink << m[1] }
    end

    # ---- text scanning helpers ---------------------------------------

    # True when `keyword` sits at `index` as a standalone word (not part of
    # a longer identifier).
    private def keyword_at?(chars : Array(Char), index : Int32, keyword : String) : Bool
      return false if index + keyword.size > chars.size
      keyword.each_char_with_index { |ch, offset| return false unless chars[index + offset] == ch }
      before = index.zero? ? ' ' : chars[index - 1]
      after_index = index + keyword.size
      after = after_index < chars.size ? chars[after_index] : ' '
      !identifier_char?(before) && !identifier_char?(after)
    end

    private def identifier_char?(ch : Char) : Bool
      ch.ascii_alphanumeric? || ch == '_'
    end

    private def skip_whitespace(chars : Array(Char), index : Int32) : Int32
      i = index
      while i < chars.size && chars[i].ascii_whitespace?
        i += 1
      end
      i
    end

    private def slice_chars(chars : Array(Char), from : Int32, to : Int32) : String
      String.build { |io| (from...to).each { |i| io << chars[i] } }
    end

    # Index of the delimiter matching the opener at `open_index` (`(`→`)`
    # or `{`→`}`), skipping string/char literals and comments. nil when the
    # source is unbalanced. Single O(n) forward pass over the char array.
    private def matching_delimiter(chars : Array(Char), open_index : Int32) : Int32?
      opener = chars[open_index]
      closer = opener == '(' ? ')' : '}'
      depth = 0
      i = open_index
      size = chars.size
      in_string = in_char = escape = in_line_comment = in_block_comment = false

      while i < size
        ch = chars[i]
        nxt = i + 1 < size ? chars[i + 1] : '\0'

        if in_line_comment
          in_line_comment = false if ch == '\n'
        elsif in_block_comment
          if ch == '*' && nxt == '/'
            in_block_comment = false
            i += 2
            next
          end
        elsif in_string
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == '"'
            in_string = false
          end
        elsif in_char
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == '\''
            in_char = false
          end
        else
          case ch
          when '/'
            if nxt == '/'
              in_line_comment = true
              i += 2
              next
            elsif nxt == '*'
              in_block_comment = true
              i += 2
              next
            end
          when '"'    then in_string = true
          when '\''   then in_char = true
          when opener then depth += 1
          when closer
            depth -= 1
            return i if depth.zero?
          end
        end

        i += 1
      end

      nil
    end

    # ---- AST helpers -------------------------------------------------

    # Record a class/method declaration under its simple name. First
    # declaration wins so an overload (or shadowing nested class) doesn't
    # clobber the primary one.
    private def index_decl(node : LibTreeSitter::TSNode,
                           content : String,
                           index : Hash(String, LibTreeSitter::TSNode))
      name_node = Noir::TreeSitter.field(node, "name")
      return unless name_node
      key = Noir::TreeSitter.node_text(name_node, content)
      index[key] ||= node
    end

    private def argument_nodes(args : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      nodes = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) do |child|
        type = Noir::TreeSitter.node_type(child)
        next if type == "line_comment" || type == "block_comment"
        nodes << child
      end
      nodes
    end

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      result = nil
      Noir::TreeSitter.each_named_child(node) { |child| result ||= child }
      result
    end

    private def walk(node : LibTreeSitter::TSNode, depth : Int32 = 0, &block : LibTreeSitter::TSNode ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, depth + 1, &block)
      end
    end

    # ---- string / path resolution ------------------------------------

    private def resolve_string(node : LibTreeSitter::TSNode,
                               content : String,
                               constants : Hash(String, String),
                               depth : Int32 = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, content)
      when "identifier", "field_access"
        resolve_constant(Noir::TreeSitter.node_text(node, content), constants)
      when "binary_expression"
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        return unless Noir::TreeSitter.node_text(node, content).includes?("+")
        left_value = resolve_string(left, content, constants, depth + 1)
        right_value = resolve_string(right, content, constants, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        inner = first_named_child(node)
        inner ? resolve_string(inner, content, constants, depth + 1) : nil
      end
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, content : String) : String
      String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          io << Noir::TreeSitter.node_text(child, content) if Noir::TreeSitter.node_type(child) == "string_fragment"
        end
      end
    end

    private def resolve_constant(name : String, constants : Hash(String, String)) : String?
      if value = constants[name]?
        return value
      end

      suffix = ".#{name.split('.').last}"
      matches = constants.compact_map { |key, val| key.ends_with?(suffix) ? val : nil }.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def simple_name(type_text : String) : String
      type_text.split('<').first.split('.').last.strip
    end

    private def normalize_path(path : String) : String
      np = path.strip
      np = "/#{np}" unless np.starts_with?("/")
      np = np.gsub(%r{/+}, "/")
      np = np[0...-1] if np.ends_with?("/") && np != "/"
      np.empty? ? "/" : np
    end

    private def valid_path?(path : String) : Bool
      return false if path.empty?
      return false unless path.starts_with?("/")
      return false if path.includes?(' ')
      path.size <= 200
    end
  end
end
