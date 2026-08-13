require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # Alfred (`package:alfred/alfred.dart`) is a minimalist, Express-style
  # Dart server framework. Routes are registered against an `Alfred()`
  # instance with a method per verb:
  #
  #   final app = Alfred();
  #   app.get('/users', (req, res) => _listUsers(req));
  #   app.post('/users', _createUser);
  #   app.get('/users/:id', (req, res) => _getUser(req));
  #   app.all('*', _catchAll);
  #
  # Path captures use Express-style `:id` segments, optionally with a
  # type matcher (`:id:int`, `:date:date`) which we strip down to the
  # `{id}` / `{date}` path-param form. `.all(...)` registers a handler
  # against every verb.
  #
  # Routes are collected per file against the variable bound to an
  # `Alfred()` instance (or a parameter/field typed `Alfred`), so calls
  # on unrelated receivers (e.g. `someMap.get('key')`) are never mistaken
  # for routes.
  class Alfred < Analyzer
    analyzer_for "dart_alfred"

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the router-variable matcher interpolates
    # a discovered name that repeats across files, so memoize it per name.
    @call_regexes = Hash(String, Regex).new

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

    def analyze
      include_callee = callees_needed?
      result = [] of Endpoint
      mutex = Mutex.new

      begin
        files = get_files_by_extension(".dart")

        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")
          # `test/` fixtures spin up real `Alfred()` instances that never
          # serve production traffic.
          next if Helper.test_path?(path, base_paths)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          next unless alfred_file?(content)

          endpoints = scan_file(content, path, include_callee)
          next if endpoints.empty?

          mutex.synchronize { result.concat(endpoints) }
        end
      rescue e
        logger.debug e
      end

      result
    end

    # A file participates in Alfred routing if it imports the package,
    # instantiates `Alfred()`, or references the `Alfred` type (route
    # registration often happens in a controller that receives the
    # instance as a constructor field — these files import a barrel that
    # re-exports `package:alfred/`, not the package directly). The real
    # gate is `router_prefixes`: nothing is emitted without an `Alfred`
    # instance/typed variable and a verb call.
    private def alfred_file?(content : String) : Bool
      content.includes?("package:alfred/") || content.matches?(/\bAlfred\b/)
    end

    # Discover variables that hold an `Alfred` instance (or a `route()`
    # child), then collect the verb calls (direct or cascade) attached to
    # each. Operates on a comment-stripped copy so offsets in the original
    # line up byte-for-byte.
    private def scan_file(content : String, path : String, include_callee : Bool) : Array(Endpoint)
      cleaned = Helper.strip_comments(content)
      prefixes = router_prefixes(cleaned)
      return [] of Endpoint if prefixes.empty?

      endpoints = [] of Endpoint
      seen = Set({String, String}).new # (verb, path) within this file

      # Direct verb calls on a router variable (`app.get('/x', h)`); the
      # variable's prefix is empty for the top-level `Alfred` instance and
      # the composed base for a `route()`-assigned child router.
      prefixes.each do |var_name, prefix|
        scan_calls(cleaned, var_name, prefix, content, path, include_callee, endpoints, seen)
      end

      # Cascade-nested routes: `app.route('/base')..get('sub', h)..post(...)`.
      scan_route_cascades(cleaned, prefixes, content, path, include_callee, endpoints, seen)

      endpoints
    end

    # Names bound to an `Alfred()` instance, plus parameters/fields whose
    # declared type is `Alfred` (so `void configure(Alfred app)` route
    # registration is picked up too).
    ALFRED_ASSIGN_REGEX = /(?:^|[;{}=(,\s])(?:final|var|const|late)\s+(?:Alfred\s+)?([A-Za-z_]\w*)\s*=\s*Alfred\s*\(/
    # An `Alfred`-typed parameter (`void f(Alfred app)`) or field
    # (`final Alfred app;`), so route registration that reaches `Alfred`
    # through a constructor/parameter is picked up.
    ALFRED_TYPED_REGEX = /(?:[;{}(,]\s*|\b(?:final|late|const|var|required)\s+)Alfred\s+([A-Za-z_]\w*)\b/
    # `final r = app.route('/base', ...)` — a NestedRoute child bound to a
    # variable. Capture 1 is the new variable, capture 2 its receiver.
    ROUTE_ASSIGN_REGEX = /(?:^|[;{}=(,\s])(?:final|var|const|late)\s+(?:[A-Za-z_][\w<>,\s?]*\s+)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*\.\s*route\s*\(/

    # Router variable → raw base prefix. Top-level `Alfred` instances and
    # `Alfred`-typed parameters map to "" (root); a `route()`-assigned child
    # maps to its composed base path.
    private def router_prefixes(cleaned : String) : Hash(String, String)
      prefixes = {} of String => String
      cleaned.scan(ALFRED_ASSIGN_REGEX) do |m|
        prefixes[m[1]] = "" unless m[1].empty?
      end
      cleaned.scan(ALFRED_TYPED_REGEX) do |m|
        prefixes[m[1]] = "" unless m[1].empty?
      end

      # Resolve `var r = <router>.route('/base')` assignments. A few passes
      # settle chained assignments (`r2 = r.route('/x')`).
      3.times do
        added = false
        cleaned.scan(ROUTE_ASSIGN_REGEX) do |m|
          name = m[1]
          recv = m[2]
          next if prefixes.has_key?(name)
          base = prefixes[recv]?
          next unless base
          open_paren = (m.end(0) || 0) - 1
          close_paren = Helper.find_matching_paren(cleaned, open_paren)
          next unless close_paren
          args = Helper.split_top_level_args(cleaned[(open_paren + 1)...close_paren])
          next if args.empty?
          sub = Helper.extract_string_literal(args[0])
          next unless sub
          prefixes[name] = alfred_compose(base, sub)
          added = true
        end
        break unless added
      end

      prefixes
    end

    # Direct `app.get('/x', h)` verb calls on the router variable. `route`
    # and other non-verb members are filtered by `relevant_method?`.
    private def scan_calls(cleaned : String,
                           var_name : String,
                           prefix : String,
                           content : String,
                           path : String,
                           include_callee : Bool,
                           endpoints : Array(Endpoint),
                           seen : Set({String, String}))
      pattern = @call_regexes[var_name] ||= /(?<![\w$])#{Regex.escape(var_name)}\s*\.\s*([a-zA-Z]+)\s*\(/
      cleaned.scan(pattern) do |m|
        method = m[1]
        next unless relevant_method?(method)
        match_end = m.end(0)
        next unless match_end
        open_paren = match_end - 1
        close_paren = Helper.find_matching_paren(cleaned, open_paren)
        next unless close_paren
        handle_call(method, cleaned, open_paren, close_paren, prefix, content, path, include_callee, endpoints, seen)
      end
    end

    # A `route()` call whose result a cascade/chain of verb calls is
    # attached to: `app.route('/base')..get('sub', h)..post('sub2', h)`.
    ROUTE_CALL_REGEX = /(?<![\w$.])([A-Za-z_]\w*)\s*\.\s*route\s*\(/

    private def scan_route_cascades(cleaned : String,
                                    prefixes : Hash(String, String),
                                    content : String,
                                    path : String,
                                    include_callee : Bool,
                                    endpoints : Array(Endpoint),
                                    seen : Set({String, String}))
      cleaned.scan(ROUTE_CALL_REGEX) do |m|
        rvar = m[1]
        base = prefixes[rvar]?
        next unless base
        open_paren = (m.end(0) || 0) - 1
        close_paren = Helper.find_matching_paren(cleaned, open_paren)
        next unless close_paren
        args = Helper.split_top_level_args(cleaned[(open_paren + 1)...close_paren])
        next if args.empty?
        sub = Helper.extract_string_literal(args[0])
        next unless sub

        base_prefix = alfred_compose(base, sub)
        scan_chain(cleaned, close_paren + 1, base_prefix, content, path, include_callee, endpoints, seen)
      end
    end

    # Walk the cascade/chain of calls following a `route()` result,
    # structurally skipping each call's handler body. A `..verb('sub', h)`
    # registers `compose(base, sub)`; a single-dot `.route('/x')` chains a
    # deeper base, while a cascade `..route('/x')` is discarded (its result
    # isn't the chain's value). The walk stops at the statement terminator.
    private def scan_chain(cleaned : String,
                           start : Int32,
                           base_prefix : String,
                           content : String,
                           path : String,
                           include_callee : Bool,
                           endpoints : Array(Endpoint),
                           seen : Set({String, String}))
      stmt_end = find_statement_end(cleaned, start)
      prefix = base_prefix
      i = start
      # `String#[]` re-walks from byte 0 on every call once the source
      # contains any multi-byte char, turning this scan O(n^2); index a
      # materialized Array(Char) instead (O(1) per access).
      chars = cleaned.chars

      while i < stmt_end
        while i < stmt_end && chars[i].whitespace?
          i += 1
        end
        break unless i < stmt_end && chars[i] == '.'
        i += 1
        cascade = false
        if i < stmt_end && chars[i] == '.'
          cascade = true
          i += 1
        end
        while i < stmt_end && chars[i].whitespace?
          i += 1
        end

        name_start = i
        while i < stmt_end && (chars[i].alphanumeric? || chars[i] == '_')
          i += 1
        end
        name = chars[name_start...i].join
        while i < stmt_end && chars[i].whitespace?
          i += 1
        end
        break unless i < stmt_end && chars[i] == '('

        open_paren = i
        close_paren = Helper.find_matching_paren(cleaned, open_paren)
        break unless close_paren && close_paren <= stmt_end

        if relevant_method?(name)
          handle_call(name, cleaned, open_paren, close_paren, prefix, content, path, include_callee, endpoints, seen)
        elsif name == "route" && !cascade
          # `.route('/x')` (chained, not a cascade) deepens the base.
          inner = Helper.split_top_level_args(cleaned[(open_paren + 1)...close_paren])
          if sub = (inner.empty? ? nil : Helper.extract_string_literal(inner[0]))
            prefix = alfred_compose(prefix, sub)
          end
        end

        i = close_paren + 1
      end
    end

    private def relevant_method?(name : String) : Bool
      HTTP_METHOD_MAP.has_key?(name) || name == "all"
    end

    private def handle_call(method : String,
                            source : String,
                            open_paren : Int32,
                            close_paren : Int32,
                            prefix : String,
                            content : String,
                            path : String,
                            include_callee : Bool,
                            endpoints : Array(Endpoint),
                            seen : Set({String, String}))
      return if open_paren >= close_paren
      args = Helper.split_top_level_args(source[(open_paren + 1)...close_paren])
      # A route always carries a handler, so a single-arg call (e.g. a
      # stray `obj.get('key')`) is not a route.
      return if args.size < 2

      literal = Helper.extract_string_literal(args[0])
      return unless literal

      url = prefix.empty? ? normalize_path(literal) : normalize_path(alfred_compose(prefix, literal))
      line = line_number_for_index(content, open_paren)

      callees = [] of Noir::DartCalleeExtractor::Entry
      if include_callee
        # The handler is the second argument: it begins right after the
        # first top-level comma. Pinning the start here (rather than
        # `close_paren - handler.size`) keeps body extraction correct when
        # a trailing `middleware: [...]` argument follows the handler.
        comma = Helper.first_top_level_comma(source, open_paren + 1, close_paren)
        callees = Helper.handler_callees(args[1], content, comma + 1, path, line) if comma
      end

      verbs = method == "all" ? ALL_VERBS : [HTTP_METHOD_MAP[method]]
      verbs.each do |verb|
        next unless seen.add?({verb, url})
        endpoints << Helper.build_endpoint(url, verb, path, line, callees)
      end
    end

    # Ensure a leading slash and translate Express-style `:id` / `:id:int`
    # captures into `{id}` path params. The optional `:type` matcher
    # (`int`, `date`, `uuid`, ...) is dropped.
    private def normalize_path(path : String) : String
      base = path.starts_with?('/') ? path : "/#{path}"
      base.gsub(/:([A-Za-z_]\w*)(?::[A-Za-z_]\w*)?/) { "{#{$~[1]}}" }
    end

    # Join a `route()` base with a sub-path exactly as Alfred's
    # `NestedRoute._composePath` does, so composed URLs match the framework.
    private def alfred_compose(first : String, second : String) : String
      if first.ends_with?('/') && second.starts_with?('/')
        first + second[1..]
      elsif !first.ends_with?('/') && !second.starts_with?('/')
        "#{first}/#{second}"
      else
        first + second
      end
    end

    # ---------- Source-string utilities ----------

    # Char index just past the end of the statement beginning at `start`:
    # the first `;` at bracket depth zero (or end of source). Used to bound
    # a `route()` cascade/chain walk so it can't run into the next statement.
    private def find_statement_end(text : String, start : Int32) : Int32
      chars = text.chars
      depth = 0
      i = start
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]
        if in_string
          if c == '\\' && i + 1 < chars.size
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
        when '(', '{', '['
          depth += 1
        when ')', '}', ']'
          depth -= 1 if depth > 0
        when ';'
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end
      chars.size
    end
  end
end
