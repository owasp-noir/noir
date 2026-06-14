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
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
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

    private def alfred_file?(content : String) : Bool
      content.includes?("package:alfred/") || content.includes?("Alfred(")
    end

    # Discover variables that hold an `Alfred` instance, then collect the
    # verb calls (cascade or direct) attached to each. Operates on a
    # comment-stripped copy so offsets in the original line up byte-for-byte.
    private def scan_file(content : String, path : String, include_callee : Bool) : Array(Endpoint)
      cleaned = Helper.strip_comments(content)
      router_vars = alfred_router_vars(cleaned)
      return [] of Endpoint if router_vars.empty?

      endpoints = [] of Endpoint
      seen = Set({String, String}).new # (verb, path) within this file

      router_vars.each do |var_name|
        scan_calls(cleaned, var_name, content, path, include_callee, endpoints, seen)
      end

      endpoints
    end

    # Names bound to an `Alfred()` instance, plus parameters/fields whose
    # declared type is `Alfred` (so `void configure(Alfred app)` route
    # registration is picked up too).
    ALFRED_ASSIGN_REGEX = /(?:^|[;{}=(,\s])(?:final|var|const|late)\s+(?:Alfred\s+)?([A-Za-z_]\w*)\s*=\s*Alfred\s*\(/
    ALFRED_TYPED_REGEX  = /(?:^|[;{}(,])\s*Alfred\s+([A-Za-z_]\w*)/

    private def alfred_router_vars(cleaned : String) : Array(String)
      vars = Set(String).new
      cleaned.scan(ALFRED_ASSIGN_REGEX) do |m|
        name = m[1]
        vars << name unless name.empty?
      end
      cleaned.scan(ALFRED_TYPED_REGEX) do |m|
        name = m[1]
        vars << name unless name.empty?
      end
      vars.to_a
    end

    # Both cascade (`..get(`) and direct (`app.get(`) calls reference the
    # router variable. A single regex over the cleaned source matches
    # `app.get(` and `..get(` (the optional `.` before the receiver lets
    # the same scan catch cascades); `mount`/`route` and other non-verb
    # members are filtered by `relevant_method?`.
    private def scan_calls(cleaned : String,
                           var_name : String,
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
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren
        handle_call(method, cleaned, open_paren, close_paren, content, path, include_callee, endpoints, seen)
      end
    end

    private def relevant_method?(name : String) : Bool
      HTTP_METHOD_MAP.has_key?(name) || name == "all"
    end

    private def handle_call(method : String,
                            source : String,
                            open_paren : Int32,
                            close_paren : Int32,
                            content : String,
                            path : String,
                            include_callee : Bool,
                            endpoints : Array(Endpoint),
                            seen : Set({String, String}))
      return if open_paren >= close_paren
      args = split_top_level_args(source[(open_paren + 1)...close_paren])
      # A route always carries a handler, so a single-arg call (e.g. a
      # stray `obj.get('key')`) is not a route.
      return if args.size < 2

      literal = Helper.extract_string_literal(args[0])
      return unless literal

      url = normalize_path(literal)
      line = line_for_offset(content, open_paren)

      callees = [] of Noir::DartCalleeExtractor::Entry
      if include_callee
        # The handler is the second argument: it begins right after the
        # first top-level comma. Pinning the start here (rather than
        # `close_paren - handler.size`) keeps body extraction correct when
        # a trailing `middleware: [...]` argument follows the handler.
        comma = first_top_level_comma(source, open_paren + 1, close_paren)
        callees = handler_callees(args[1], content, comma + 1, path, line) if comma
      end

      verbs = method == "all" ? ALL_VERBS : [HTTP_METHOD_MAP[method]]
      verbs.each do |verb|
        next unless seen.add?({verb, url})
        endpoints << build_endpoint(url, verb, path, line, callees)
      end
    end

    # Matches a bare handler reference (`_createUser`, `auth.handler`)
    # passed as a route's handler argument.
    HANDLER_REFERENCE_REGEX = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/

    private def handler_callees(handler_arg : String,
                                content : String,
                                handler_start : Int32,
                                path : String,
                                line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      stripped = handler_arg.strip

      # A plain function reference (`_createUser`, `auth.handler`) can't be
      # resolved cross-file yet, so record the reference itself as the callee.
      unless stripped.starts_with?('(')
        return [] of Noir::DartCalleeExtractor::Entry unless stripped.matches?(HANDLER_REFERENCE_REGEX)
        return [{stripped, path, line}] of Noir::DartCalleeExtractor::Entry
      end

      # handler_start is a CHAR index into the source; extract_body_after
      # scans by BYTE offset. `extract_body_after` skips past the leading
      # `(req, res)` lambda params to the `=>`/`{` body, so a trailing
      # `middleware:` argument after the body is naturally excluded.
      start_b = content.char_index_to_byte_index(handler_start)
      return [] of Noir::DartCalleeExtractor::Entry unless start_b
      body_info = Noir::DartCalleeExtractor.extract_body_after(content, start_b)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    # Ensure a leading slash and translate Express-style `:id` / `:id:int`
    # captures into `{id}` path params. The optional `:type` matcher
    # (`int`, `date`, `uuid`, ...) is dropped.
    private def normalize_path(path : String) : String
      base = path.starts_with?('/') ? path : "/#{path}"
      base.gsub(/:([A-Za-z_]\w*)(?::[A-Za-z_]\w*)?/) { "{#{$~[1]}}" }
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

    # Char-based matching `)` for the `(` at `open_idx`, so the returned
    # offset stays in CHAR space (consistent with `line_for_offset` and the
    # `char_index_to_byte_index` conversions used for callee extraction).
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

    # Char index of the first comma at paren/brace/bracket depth zero
    # between `start` and `limit`, or nil when the call has a single
    # argument.
    private def first_top_level_comma(text : String, start : Int32, limit : Int32) : Int32?
      depth = 0
      i = start
      in_string = false
      string_quote = '\0'

      while i < limit
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
        when '(', '{', '['
          depth += 1
        when ')', '}', ']'
          depth -= 1 if depth > 0
        when ','
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
