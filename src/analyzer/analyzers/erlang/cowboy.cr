require "../../../models/analyzer"
require "./erlang_helper"
require "set"

module Analyzer::Erlang
  # Cowboy keeps its routes in a dispatch table rather than in per-handler
  # annotations:
  #
  #     Dispatch = cowboy_router:compile([
  #         {'_', [
  #             {"/",             hello_handler, []},
  #             {"/users/:id",    user_handler,  []},
  #             {"/static/[...]", cowboy_static, {priv_dir, app, "static"}}
  #         ]}
  #     ]),
  #
  # The verb is deliberately absent from the table — Cowboy leaves method
  # negotiation to the handler (`allowed_methods/2` for REST handlers, or
  # a match on `cowboy_req:method/1`). Resolving it therefore means
  # following the handler atom to its module, which is what
  # `handler_info` does; routes whose handler can't be resolved fall back
  # to "ANY".
  class Cowboy < Analyzer
    # Cowboy dispatch entries are `{PathMatch, Handler, InitialState}` or
    # `{PathMatch, Constraints, Handler, InitialState}`, and PathMatch is
    # always an absolute path — as a string or as a binary. Requiring the
    # leading `/` right in the gate keeps every other Erlang tuple out.
    ROUTE_TUPLE_START = /\{\s*(?:"\/|<<\s*"\/)/
    PATH_LITERAL      = /\A\s*(?:"((?:[^"\\]|\\.)*)"|<<\s*"((?:[^"\\]|\\.)*)"\s*>>)\s*\z/
    HANDLER_ATOM      = /\A[a-z][A-Za-z0-9_@]*\z/

    # A dispatch tuple that spans more lines than this is not a shape we
    # can read; bounding the window also bounds the joined-text cost so a
    # pathological file can't turn the scan quadratic.
    MAX_TUPLE_LINES = 20

    HTTP_VERBS = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"}

    # `cowboy_static` is Cowboy's built-in file handler. It never reaches
    # user code, so there is no `allowed_methods/2` to follow — but it
    # only ever serves GET and HEAD.
    STATIC_HANDLER = "cowboy_static"

    ALLOWED_METHODS_REGEX = /allowed_methods\s*\([^)]*\)\s*->\s*\{\s*\[([^\]]*)\]/
    METHOD_BINARY_REGEX   = /<<\s*"([A-Za-z]+)"\s*>>/
    REQ_METHOD_REGEX      = /cowboy_req:method\s*\(/

    BINDING_REGEX      = /cowboy_req:binding\s*\(\s*([a-z][A-Za-z0-9_@]*)/
    MATCH_QS_START     = /cowboy_req:match_qs\s*\(\s*\[/
    MATCH_COOKIE_START = /cowboy_req:match_cookies\s*\(\s*\[/
    HEADER_REGEX       = /cowboy_req:header\s*\(\s*<<\s*"([^"]+)"\s*>>/
    URLENCODED_REGEX   = /cowboy_req:read_urlencoded_body\s*\(/
    READ_BODY_REGEX    = /cowboy_req:read_(?:body|part)\s*\(/
    # A match_qs field is either a bare atom (`id`) or a constraint tuple
    # whose first element is the field name (`{token, nonempty}`,
    # `{page, int, 1}`). Only that leading atom is the parameter — the
    # rest is the constraint and its default.
    QS_FIELD_REGEX = /\A\{?\s*([a-z][A-Za-z0-9_@]*)/

    # Verbs that can carry a request body. Handler params are collected
    # per module rather than per clause, so a module that both serves GET
    # and reads a body on POST would otherwise hang a body param off its
    # GET route.
    BODY_VERBS = Set{"POST", "PUT", "PATCH", "ANY"}

    record HandlerInfo, methods : Array(String), params : Array(Param)

    @handler_cache = {} of String => HandlerInfo?

    def analyze
      erlang_files = erlang_sources
      return @result if erlang_files.empty?

      module_index = build_module_index(erlang_files)

      erlang_files.each do |path|
        content = read_file_content(path)
        # Cheap reject before the comment strip: a file with no
        # `{"/…` / `{<<"/…` tuple can't hold a dispatch table.
        next unless content.matches?(ROUTE_TUPLE_START)

        process_file(path, content, module_index)
      end

      @result
    end

    private def erlang_sources : Array(String)
      files = get_files_by_extension(".erl") + get_files_by_extension(".hrl")
      files.reject! { |path| File.directory?(path) }
      files
    end

    # Erlang requires the module name to match the file name, so the
    # basename is a reliable index key. Keyed per configured base so a
    # monorepo doesn't resolve a handler across unrelated projects.
    private def build_module_index(files : Array(String)) : Hash(Tuple(String, String), String)
      index = {} of Tuple(String, String) => String
      files.each do |path|
        next unless path.ends_with?(".erl")
        index[{configured_base_for(path), File.basename(path, ".erl")}] ||= path
      end
      index
    end

    private def process_file(path : String,
                             content : String,
                             module_index : Hash(Tuple(String, String), String))
      cleaned = Helper.strip_erlang_comments(content)
      lines = cleaned.lines

      lines.each_with_index do |line, idx|
        next unless line.matches?(ROUTE_TUPLE_START)

        window_end = Math.min(idx + MAX_TUPLE_LINES, lines.size - 1)
        window = lines[idx..window_end].join("\n")

        offset = 0
        while m = ROUTE_TUPLE_START.match(line, offset)
          start = m.begin(0)
          if tuple = balanced_span(window, start, '{', '}')
            emit_route(path, idx + 1, tuple, module_index)
          end
          offset = start + 1
        end
      end
    end

    # Returns the text of the balanced `open_char`..`close_char` span
    # beginning at `open_idx`, delimiters included, or nil if it never
    # closes. Quoted strings and atoms are skipped so a delimiter inside
    # `"{"` doesn't unbalance the count.
    private def balanced_span(text : String,
                              open_idx : Int32,
                              open_char : Char,
                              close_char : Char) : String?
      chars = text.chars
      return unless chars[open_idx]? == open_char

      depth = 0
      i = open_idx
      while i < chars.size
        c = chars[i]

        if c == '"' || c == '\''
          quote = c
          i += 1
          while i < chars.size
            ch = chars[i]
            if ch == '\\' && i + 1 < chars.size
              i += 2
              next
            end
            i += 1
            break if ch == quote
          end
          next
        end

        if c == open_char
          depth += 1
        elsif c == close_char
          depth -= 1
          return text[open_idx..i] if depth == 0
        end

        i += 1
      end

      nil
    end

    private def emit_route(path : String,
                           line : Int32,
                           tuple : String,
                           module_index : Hash(Tuple(String, String), String))
      # `{Path, handler, State} || {Path, State} <- Routes` builds the
      # table by list comprehension. The tuple is shaped exactly like a
      # literal route, but its path comes from the generator, so anything
      # read out of the template would be fiction.
      return if tuple.includes?("||")

      elements = split_top_level(tuple[1...-1])
      # Cowboy dispatch entries are exactly 3- or 4-element tuples. A
      # shorter one is some other tuple that happens to lead with a path.
      return unless elements.size == 3 || elements.size == 4

      path_match = extract_path_literal(elements[0])
      return unless path_match

      # `{PathMatch, Constraints, Handler, State}` puts a (possibly
      # empty) constraints list in slot 1; the 3-tuple puts the handler
      # there.
      handler_raw = if elements.size == 4 && elements[1].strip.starts_with?('[')
                      elements[2]
                    else
                      elements[1]
                    end
      handler = normalize_handler(handler_raw)
      return unless handler

      url, path_params = Helper.parse_cowboy_path(path_match)
      info = handler_info(handler, path, module_index)

      methods = info ? info.methods : [] of String
      methods = [STATIC_HANDLER == handler ? "GET" : "ANY"] if methods.empty?

      methods.each do |method|
        params = path_params.dup
        if info
          seen = params.map(&.name).to_set
          info.params.each do |param|
            next if param.param_type == "path" && seen.includes?(param.name)
            next if param.param_type == "body" && !BODY_VERBS.includes?(method)
            params << param
          end
        end

        details = Details.new(PathInfo.new(path, line))
        @result << Endpoint.new(url, method, params, details)
      end
    end

    private def extract_path_literal(element : String) : String?
      m = element.match(PATH_LITERAL)
      return unless m
      m[1]? || m[2]?
    end

    # The handler slot is a module atom (`user_handler`), a quoted atom,
    # or a `{Module, Function}` pair. Anything else means this tuple was
    # never a route.
    private def normalize_handler(raw : String) : String?
      candidate = raw.strip
      if candidate.starts_with?('{')
        inner = split_top_level(candidate[1...-1])
        return if inner.empty?
        candidate = inner[0].strip
      end
      candidate = candidate.strip('\'')
      return unless candidate.matches?(HANDLER_ATOM)
      candidate
    end

    private def handler_info(handler : String,
                             route_path : String,
                             module_index : Hash(Tuple(String, String), String)) : HandlerInfo?
      return if handler == STATIC_HANDLER

      key = "#{configured_base_for(route_path)}\0#{handler}"
      return @handler_cache[key] if @handler_cache.has_key?(key)

      handler_path = module_index[{configured_base_for(route_path), handler}]?
      info = handler_path ? parse_handler(handler_path) : nil
      @handler_cache[key] = info
      info
    end

    private def parse_handler(path : String) : HandlerInfo
      content = Helper.strip_erlang_comments(read_file_content(path))

      HandlerInfo.new(handler_methods(content), handler_params(content))
    end

    private def handler_methods(content : String) : Array(String)
      methods = [] of String
      seen = Set(String).new

      # A REST handler declares its verbs outright.
      if m = content.match(ALLOWED_METHODS_REGEX)
        m[1].scan(METHOD_BINARY_REGEX) do |binary|
          verb = binary[1].upcase
          methods << verb if HTTP_VERBS.includes?(verb) && seen.add?(verb)
        end
        return methods unless methods.empty?
      end

      # A plain handler branches on `cowboy_req:method/1` instead. Every
      # HTTP-verb binary in such a module is a verb it handles.
      if content.matches?(REQ_METHOD_REGEX)
        content.scan(METHOD_BINARY_REGEX) do |binary|
          verb = binary[1].upcase
          methods << verb if HTTP_VERBS.includes?(verb) && seen.add?(verb)
        end
      end

      methods
    end

    private def handler_params(content : String) : Array(Param)
      params = [] of Param
      seen = Set(Tuple(String, String)).new

      content.scan(BINDING_REGEX) do |m|
        name = m[1]
        params << Param.new(name, "", "path") if seen.add?({name, "path"})
      end

      each_field_list(content, MATCH_QS_START) do |field|
        params << Param.new(field, "", "query") if seen.add?({field, "query"})
      end

      each_field_list(content, MATCH_COOKIE_START) do |field|
        params << Param.new(field, "", "cookie") if seen.add?({field, "cookie"})
      end

      content.scan(HEADER_REGEX) do |m|
        name = m[1]
        params << Param.new(name, "", "header") if seen.add?({name, "header"})
      end

      if content.matches?(URLENCODED_REGEX)
        params << Param.new("body", "Form", "body") if seen.add?({"body", "body"})
      elsif content.matches?(READ_BODY_REGEX)
        params << Param.new("body", "", "body") if seen.add?({"body", "body"})
      end

      params
    end

    # Yields each field name from every `[...]` list introduced by
    # `start_regex`. The list is read by balanced scan rather than by a
    # `[^\]]*` capture, which would stop at the first inner `]` — and
    # constraint entries such as `{fields, [], undefined}` embed one.
    private def each_field_list(content : String, start_regex : Regex, &)
      offset = 0
      while m = start_regex.match(content, offset)
        bracket = m.end(0) - 1
        if list = balanced_span(content, bracket, '[', ']')
          split_top_level(list[1...-1]).each do |entry|
            if field = entry.match(QS_FIELD_REGEX)
              yield field[1]
            end
          end
        end
        offset = m.end(0)
      end
    end

    # Splits an Erlang tuple/list body on its top-level commas, ignoring
    # commas nested in strings, quoted atoms, tuples, lists or binaries.
    private def split_top_level(body : String) : Array(String)
      parts = [] of String
      current = String::Builder.new
      depth = 0
      i = 0
      chars = body.chars

      while i < chars.size
        c = chars[i]

        if c == '"' || c == '\''
          quote = c
          current << c
          i += 1
          while i < chars.size
            ch = chars[i]
            if ch == '\\' && i + 1 < chars.size
              current << ch
              current << chars[i + 1]
              i += 2
              next
            end
            current << ch
            i += 1
            break if ch == quote
          end
          next
        end

        case c
        when '{', '[', '('
          depth += 1
          current << c
        when '}', ']', ')'
          depth -= 1
          current << c
        when ','
          if depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << c
          end
        else
          current << c
        end

        i += 1
      end

      tail = current.to_s
      parts << tail unless tail.strip.empty?
      parts.map(&.strip)
    end
  end
end
