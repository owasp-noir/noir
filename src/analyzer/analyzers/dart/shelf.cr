require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # Shelf (`package:shelf_router/shelf_router.dart`) is the foundational
  # Dart HTTP server library. The `Router` API exposes a method per
  # verb (`router.get`, `router.post`, ...) and a `mount('/prefix',
  # subRouter)` composition primitive. Handlers are typically wired
  # with cascade operators on a fresh `Router()`:
  #
  #   final router = Router()
  #     ..get('/users', _listUsers)
  #     ..post('/users', _createUser)
  #     ..get('/users/<id>', _getUser)
  #     ..mount('/api/v1', apiRouter.call);
  #
  # Direct method calls (`router.get('/foo', _handler)`) and `.all(...)`
  # — which registers a handler against every verb — are also
  # supported. Path captures use angle brackets (`<id>`, `<id|[0-9]+>`)
  # which we surface as `{id}` path params.
  #
  # Mounts are resolved across files: a `Router` variable mounted under
  # `/prefix` contributes its routes (recursively) under that prefix in
  # the parent router. Each top-level router (not mounted anywhere) is
  # emitted as a separate set of endpoints.
  class Shelf < Analyzer
    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the router-variable matcher interpolates
    # a discovered name (`router`, `app`, ...) that repeats across files,
    # so memoize it per name.
    @direct_call_regexes = Hash(String, Regex).new

    HTTP_METHOD_MAP = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "patch"   => "PATCH",
      "delete"  => "DELETE",
      "head"    => "HEAD",
      "options" => "OPTIONS",
    }

    ALL_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    alias RouterKey = Tuple(String, String)

    alias Route = NamedTuple(
      verb: String,
      path: String,
      line: Int32,
      file: String,
      callees: Array(Noir::DartCalleeExtractor::Entry))

    alias Mount = NamedTuple(prefix: String, child: String)

    alias RouterInfo = NamedTuple(
      routes: Array(Route),
      mounts: Array(Mount))

    def analyze
      include_callee = callees_needed?
      mutex = Mutex.new
      routers = {} of RouterKey => RouterInfo

      begin
        files = get_files_by_extension(".dart")

        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")
          # Skip `test/` routers — `dart test` fixtures spin up real
          # `Router()` instances that never serve production traffic.
          next if Helper.test_path?(path, base_paths)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          next unless shelf_file?(content)

          file_routers = scan_file(content, path, include_callee)
          next if file_routers.empty?

          base_path = configured_base_for(path)
          mutex.synchronize do
            file_routers.each do |name, info|
              key = router_key(base_path, name)
              existing = routers[key]?
              if existing
                routers[key] = {
                  routes: existing[:routes] + info[:routes],
                  mounts: existing[:mounts] + info[:mounts],
                }
              else
                routers[key] = info
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      assemble_endpoints(routers)
    end

    private def router_key(base_path : String, name : String) : RouterKey
      {base_path, name}
    end

    private def shelf_file?(content : String) : Bool
      return true if content.includes?("package:shelf_router/")
      return true if content.includes?("package:shelf/shelf.dart") && content.includes?("Router(")
      false
    end

    # Locate every `Router()` instantiation bound to a variable and
    # collect routes and mounts attached to that router via cascade
    # chains (`..get(...)`) or direct method calls (`router.get(...)`).
    # Operates on a comment-stripped copy of the source so offsets in
    # the original file line up byte-for-byte.
    private def scan_file(content : String,
                          path : String,
                          include_callee : Bool) : Hash(String, RouterInfo)
      result = {} of String => RouterInfo
      cleaned = strip_dart_comments(content)
      classes = class_ranges(cleaned)

      cleaned.scan(/(?:^|[;{}=(,\s])(?:final|var|const|late)\s+(?:[A-Za-z_][\w<>,\s\?]*\s+)?([A-Za-z_]\w*)\s*=\s*Router\s*\(\s*\)/) do |match|
        var_name = match[1]
        next if var_name.empty?
        end_idx = match.end(0)
        next unless end_idx

        cascade_end = find_statement_end(cleaned, end_idx)

        routes = [] of Route
        mounts = [] of Mount

        # Cascades attached directly to the `Router()` expression.
        scan_cascades(cleaned, end_idx, cascade_end, content, path, include_callee, routes, mounts)

        # Direct method calls referencing the router variable elsewhere
        # in the file. We scan the cleaned source so refs inside
        # strings or comments are ignored.
        scan_direct_calls(cleaned, var_name, content, path, include_callee, routes, mounts)

        # A router built inside a class (e.g. a `Router get router =>`
        # getter) is reached from the outside as `ClassName().router`,
        # so key it under the class name — that's what a parent's
        # `mount('/prefix', ClassName().router)` resolves against. The
        # internal local name (`app`, `router`, ...) is only meaningful
        # within the class and would otherwise be emitted, unmounted, as
        # a duplicate root with no prefix.
        key = enclosing_class(classes, end_idx) || var_name

        existing = result[key]?
        if existing
          result[key] = {
            routes: existing[:routes] + routes,
            mounts: existing[:mounts] + mounts,
          }
        else
          result[key] = {routes: routes, mounts: mounts}
        end
      end

      # `shelf_router` also supports a code-gen style where handlers are
      # annotated with `@Route.<verb>('/path')` inside a controller class
      # and wired up by a generated `_$ClassRouter`. Surface those too.
      scan_route_annotations(cleaned, content, path, include_callee, classes, result)

      result
    end

    # Matches the official `@Route.<verb>('/path')` annotation and the
    # `shelf_router_classes` `@Route('VERB', '/path')` variant. Capture 1
    # is the dotted verb (nil for the string-arg form).
    ROUTE_ANNOTATION_REGEX = /@Route\s*(?:\.\s*([A-Za-z]+))?\s*\(/
    ROUTE_PREFIX_REGEX     = /@RoutePrefix\s*\(/

    # Collect `@Route...`-annotated handlers, keyed by their enclosing
    # controller class so a parent `mount('/p', Ctrl().router)` lines up.
    private def scan_route_annotations(cleaned : String,
                                       content : String,
                                       path : String,
                                       include_callee : Bool,
                                       classes : Array(ClassRange),
                                       result : Hash(String, RouterInfo))
      prefixes = route_prefixes(cleaned, classes)

      cleaned.scan(ROUTE_ANNOTATION_REGEX) do |m|
        match_begin = m.begin(0)
        open_paren = m.end(0).try &.- 1
        next unless match_begin && open_paren
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren

        args = split_top_level_args(cleaned[(open_paren + 1)...close_paren])
        next if args.empty?

        verbs, path_arg = annotation_verbs_and_path(m[1]?, args)
        next if verbs.empty? || path_arg.nil?

        literal = extract_string_literal(path_arg)
        next unless literal

        owner = enclosing_class(classes, match_begin)
        prefix = owner ? prefixes[owner]? : nil
        route_path = normalize_path(prefix ? join_path(prefix, normalize_path(literal)) : literal)

        line = line_for_offset(content, match_begin)
        callees = include_callee ? annotation_callees(content, close_paren, path) : [] of Noir::DartCalleeExtractor::Entry

        key = owner || "@route:#{path}"
        info = result[key]? || {routes: [] of Route, mounts: [] of Mount}
        routes = info[:routes].dup
        verbs.each do |verb|
          routes << {verb: verb, path: route_path, line: line, file: path, callees: callees}
        end
        result[key] = {routes: routes, mounts: info[:mounts]}
      end
    end

    # `@RoutePrefix('/prefix')` (shelf_router_classes) applies a common
    # prefix to every annotated route in its class.
    private def route_prefixes(cleaned : String, classes : Array(ClassRange)) : Hash(String, String)
      prefixes = {} of String => String
      cleaned.scan(ROUTE_PREFIX_REGEX) do |m|
        match_begin = m.begin(0)
        open_paren = m.end(0).try &.- 1
        next unless match_begin && open_paren
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren
        args = split_top_level_args(cleaned[(open_paren + 1)...close_paren])
        next if args.empty?
        literal = extract_string_literal(args[0])
        next unless literal
        # `@RoutePrefix` sits *above* the `class` keyword, so it isn't
        # bracketed by any class body — attribute it to the class whose
        # declaration immediately follows.
        owner = class_after(classes, match_begin)
        prefixes[owner] = normalize_path(literal) if owner
      end
      prefixes
    end

    # The class whose body opens soonest after the given offset — used to
    # bind a leading class annotation (`@RoutePrefix`) to its class.
    private def class_after(ranges : Array(ClassRange), offset : Int32) : String?
      best = nil.as(String?)
      best_start = Int32::MAX
      ranges.each do |r|
        next unless r[:start] >= offset
        if r[:start] < best_start
          best = r[:name]
          best_start = r[:start]
        end
      end
      best
    end

    private def annotation_verbs_and_path(dotted : String?, args : Array(String)) : Tuple(Array(String), String?)
      if dotted
        verb = dotted.downcase
        return {ALL_VERBS.dup, args[0]} if verb == "all"
        mapped = HTTP_METHOD_MAP[verb]?
        return {[mapped], args[0]} if mapped
        return {[] of String, nil}
      end

      # `@Route('GET', '/path')` — verb is the first string argument.
      return {[] of String, nil} if args.size < 2
      verb_lit = extract_string_literal(args[0])
      return {[] of String, nil} unless verb_lit
      verb = verb_lit.downcase
      return {ALL_VERBS.dup, args[1]} if verb == "all"
      mapped = HTTP_METHOD_MAP[verb]?
      return {[mapped], args[1]} if mapped
      {[] of String, nil}
    end

    private def annotation_callees(content : String,
                                   annotation_close : Int32,
                                   path : String) : Array(Noir::DartCalleeExtractor::Entry)
      # annotation_close is a CHAR index; extract_body_after scans by BYTE offset.
      close_b = content.char_index_to_byte_index(annotation_close + 1)
      return [] of Noir::DartCalleeExtractor::Entry unless close_b
      body_info = Noir::DartCalleeExtractor.extract_body_after(content, close_b)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    alias ClassRange = NamedTuple(name: String, start: Int32, finish: Int32)

    # Locate every `class Name { ... }` block and its byte range so a
    # `Router()` instantiation can be attributed to its enclosing class.
    private def class_ranges(cleaned : String) : Array(ClassRange)
      ranges = [] of ClassRange
      cleaned.scan(/\bclass\s+([A-Za-z_]\w*)/) do |m|
        name = m[1]
        header_end = m.end(0) # char offset
        next unless header_end
        # DartCalleeExtractor scans/returns BYTE offsets; convert char->byte going
        # in and byte->char coming out so the stored ranges stay in CHAR space and
        # line up with the char-based match offsets compared in enclosing_class.
        header_end_b = cleaned.char_index_to_byte_index(header_end)
        next unless header_end_b
        open_b = Noir::DartCalleeExtractor.find_next_code_char(cleaned, '{', header_end_b)
        next unless open_b
        close_b = Noir::DartCalleeExtractor.find_matching_delimiter(cleaned, open_b, '{', '}')
        next unless close_b
        open = cleaned.byte_index_to_char_index(open_b)
        close = cleaned.byte_index_to_char_index(close_b)
        next unless open && close
        ranges << {name: name, start: open, finish: close}
      end
      ranges
    end

    # Innermost class whose body brackets the given offset, if any.
    private def enclosing_class(ranges : Array(ClassRange), offset : Int32) : String?
      best = nil.as(String?)
      best_size = Int32::MAX
      ranges.each do |r|
        next unless offset >= r[:start] && offset <= r[:finish]
        size = r[:finish] - r[:start]
        if size < best_size
          best = r[:name]
          best_size = size
        end
      end
      best
    end

    private def scan_cascades(cleaned : String,
                              start_idx : Int32,
                              end_idx : Int32,
                              file_content : String,
                              path : String,
                              include_callee : Bool,
                              routes : Array(Route),
                              mounts : Array(Mount))
      i = start_idx
      while i < end_idx - 1
        # Match `..name(` while ignoring `...` (spread).
        if cleaned[i] == '.' && cleaned[i + 1] == '.' &&
           !(i + 2 < cleaned.size && cleaned[i + 2] == '.')
          j = i + 2
          j += 1 if j < cleaned.size && cleaned[j] == '?' # `..?name`
          name_start = j
          while j < cleaned.size && (cleaned[j].alphanumeric? || cleaned[j] == '_')
            j += 1
          end
          name = cleaned[name_start...j]
          while j < cleaned.size && cleaned[j].whitespace?
            j += 1
          end
          if j < cleaned.size && cleaned[j] == '(' && relevant_method?(name)
            close_paren = find_matching_paren(cleaned, j)
            if close_paren && close_paren < end_idx
              handle_call(name, cleaned, j, close_paren, file_content, path, include_callee, routes, mounts)
              i = close_paren + 1
              next
            end
          end
        end
        i += 1
      end
    end

    private def scan_direct_calls(cleaned : String,
                                  var_name : String,
                                  file_content : String,
                                  path : String,
                                  include_callee : Bool,
                                  routes : Array(Route),
                                  mounts : Array(Mount))
      pattern = @direct_call_regexes[var_name] ||= /(?<![\w$])#{Regex.escape(var_name)}\s*\.\s*([a-zA-Z_]\w*)\s*\(/
      cleaned.scan(pattern) do |m|
        method = m[1]
        next unless relevant_method?(method)
        match_end = m.end(0)
        next unless match_end
        open_paren = match_end - 1
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren
        handle_call(method, cleaned, open_paren, close_paren, file_content, path, include_callee, routes, mounts)
      end
    end

    private def relevant_method?(name : String) : Bool
      HTTP_METHOD_MAP.has_key?(name) || name == "all" || name == "mount"
    end

    private def handle_call(method : String,
                            source : String,
                            open_paren : Int32,
                            close_paren : Int32,
                            file_content : String,
                            path : String,
                            include_callee : Bool,
                            routes : Array(Route),
                            mounts : Array(Mount))
      return if open_paren >= close_paren
      args_text = source[(open_paren + 1)...close_paren]
      args = split_top_level_args(args_text)
      return if args.empty?

      literal = extract_string_literal(args[0])
      return unless literal

      line = line_for_offset(file_content, open_paren)

      case method
      when "mount"
        return if args.size < 2
        child = extract_mount_child(args[1])
        return unless child
        mounts << {prefix: normalize_path(literal), child: child}
      when "all"
        callees = include_callee && args.size >= 2 ? handler_callees(args[1], file_content, close_paren, path, line) : [] of Noir::DartCalleeExtractor::Entry
        ALL_VERBS.each do |verb|
          routes << {verb: verb, path: normalize_path(literal), line: line, file: path, callees: callees}
        end
      else
        verb = HTTP_METHOD_MAP[method]?
        return unless verb
        callees = include_callee && args.size >= 2 ? handler_callees(args[1], file_content, close_paren, path, line) : [] of Noir::DartCalleeExtractor::Entry
        routes << {verb: verb, path: normalize_path(literal), line: line, file: path, callees: callees}
      end
    end

    # Matches a bare handler reference (`getNotes`, `_echo`,
    # `health_check.handler`) passed as the second argument to a route.
    HANDLER_REFERENCE_REGEX = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/

    # Best-effort callee extraction for the route handler. Inline lambdas
    # have their body scanned for callees; a plain function reference
    # (Dart can't resolve these cross-file yet) is itself recorded as the
    # single callee so the handler still surfaces in AI context.
    private def handler_callees(handler_arg : String,
                                file_content : String,
                                close_paren : Int32,
                                path : String,
                                line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      stripped = handler_arg.strip

      unless stripped.starts_with?('(')
        return [] of Noir::DartCalleeExtractor::Entry unless stripped.matches?(HANDLER_REFERENCE_REGEX)
        return [{stripped, path, line}] of Noir::DartCalleeExtractor::Entry
      end

      # close_paren is a CHAR index; extract_body_after scans by BYTE offset.
      start_b = file_content.char_index_to_byte_index(close_paren - handler_arg.size)
      return [] of Noir::DartCalleeExtractor::Entry unless start_b
      body_info = Noir::DartCalleeExtractor.extract_body_after(file_content, start_b)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(file_content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def extract_mount_child(arg : String) : String?
      cleaned = arg.strip
      cleaned = cleaned.sub(/\.\s*call\b.*$/, "")
      cleaned = cleaned.sub(/\(.*$/, "")
      cleaned = cleaned.strip
      return if cleaned.empty?
      return unless cleaned.matches?(/\A[A-Za-z_]\w*\z/)
      cleaned
    end

    private def extract_string_literal(text : String) : String?
      stripped = text.strip
      return if stripped.empty?
      first = stripped[0]
      return unless first == '"' || first == '\''
      i = 1
      while i < stripped.size
        c = stripped[i]
        if c == '\\' && i + 1 < stripped.size
          i += 2
          next
        end
        return stripped[1...i] if c == first
        i += 1
      end
      nil
    end

    # `<id>` → `{id}` ; `<id|[0-9]+>` → `{id}` ; keep slashes.
    private def normalize_path(path : String) : String
      base = path.starts_with?('/') ? path : "/" + path
      base.gsub(/<([A-Za-z_]\w*)(?:\|[^>]*)?>/) { |_, m| "{#{m[1]}}" }
    end

    private def assemble_endpoints(routers : Hash(RouterKey, RouterInfo)) : Array(Endpoint)
      mounted_children = Set(RouterKey).new
      routers.each do |key, info|
        info[:mounts].each { |mnt| mounted_children << router_key(key[0], mnt[:child]) }
      end

      endpoints = [] of Endpoint
      routers.each_key do |key|
        next if mounted_children.includes?(key)
        emit_router(key, "", routers, endpoints, Set(RouterKey).new)
      end

      # Every router was mounted (cycle or stand-alone child files):
      # emit each one as a root to avoid dropping data.
      if endpoints.empty? && !routers.empty?
        routers.each_key do |key|
          emit_router(key, "", routers, endpoints, Set(RouterKey).new)
        end
      end

      endpoints
    end

    private def emit_router(key : RouterKey,
                            prefix : String,
                            routers : Hash(RouterKey, RouterInfo),
                            endpoints : Array(Endpoint),
                            visited : Set(RouterKey))
      return if visited.includes?(key)
      visited.add(key)
      info = routers[key]?
      if info
        info[:routes].each do |route|
          full_path = join_path(prefix, route[:path])
          endpoints << build_endpoint(full_path, route[:verb], route[:file], route[:line], route[:callees])
        end
        info[:mounts].each do |mnt|
          child_prefix = join_path(prefix, mnt[:prefix])
          emit_router(router_key(key[0], mnt[:child]), child_prefix, routers, endpoints, visited)
        end
      end
      visited.delete(key)
    end

    private def join_path(prefix : String, sub : String) : String
      left = prefix.rchop('/')
      right = sub.starts_with?('/') ? sub : "/#{sub}"
      result = "#{left}#{right}"
      result.empty? ? "/" : result
    end

    private def build_endpoint(url : String,
                               verb : String,
                               path : String,
                               line : Int32,
                               callees : Array(Noir::DartCalleeExtractor::Entry)) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    # ---------- Source-string utilities ----------

    private def find_statement_end(text : String, start : Int32) : Int32
      depth_paren = 0
      depth_brace = 0
      depth_bracket = 0
      i = start
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth_paren += 1
        when ')'
          depth_paren -= 1 if depth_paren > 0
        when '{'
          depth_brace += 1
        when '}'
          depth_brace -= 1 if depth_brace > 0
        when '['
          depth_bracket += 1
        when ']'
          depth_bracket -= 1 if depth_bracket > 0
        when ';'
          return i if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0
        else
          # ignore
        end
        i += 1
      end
      text.size
    end

    private def find_matching_paren(text : String, open_idx : Int32) : Int32?
      depth = 0
      i = open_idx
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    private def split_top_level_args(text : String) : Array(String)
      result = [] of String
      depth_paren = 0
      depth_brace = 0
      depth_bracket = 0
      depth_angle = 0
      start = 0
      i = 0
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth_paren += 1
        when ')'
          depth_paren -= 1 if depth_paren > 0
        when '{'
          depth_brace += 1
        when '}'
          depth_brace -= 1 if depth_brace > 0
        when '['
          depth_bracket += 1
        when ']'
          depth_bracket -= 1 if depth_bracket > 0
        when '<'
          depth_angle += 1
        when '>'
          depth_angle -= 1 if depth_angle > 0
        when ','
          if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 && depth_angle == 0
            result << text[start...i]
            start = i + 1
          end
        else
          # ignore
        end
        i += 1
      end
      result << text[start..] if start <= text.size
      result
    end

    private def strip_dart_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '/'
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          if i < chars.size
            result << chars[i]
            i += 1
          end
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '*'
          result << ' '
          result << ' '
          i += 2
          while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          if i + 1 < chars.size
            result << ' '
            result << ' '
            i += 2
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      i = 0
      while i < limit
        count += 1 if content[i] == '\n'
        i += 1
      end
      count
    end
  end
end
