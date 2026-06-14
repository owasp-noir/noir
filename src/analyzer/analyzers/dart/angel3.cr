require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # Angel3 (`package:angel3_framework/angel3_framework.dart`) is a
  # full-featured, Express-style Dart server framework. Routes are
  # registered against an `Angel()` instance with a method per verb:
  #
  #   var app = Angel();
  #   app.get('/users', (req, res) => _listUsers(req));
  #   app.post('/users', createUser);
  #   app.all('/health', (req, res) => 'ok');
  #
  # Routes can be grouped under a shared prefix with `group`, whose second
  # argument is a closure receiving a child router:
  #
  #   app.chain([cors()]).group('/api', (router) {
  #     router.get('/version', (req, res) => 'v0');   // GET /api/version
  #   });
  #
  # `group` blocks nest, composing their prefixes. Path captures use the
  # Express-style `:id` syntax, surfaced as `{id}` path params.
  #
  # Routes are bound to variables holding an `Angel()` instance (or an
  # `Angel`-typed parameter) and to the child-router parameter of a
  # `group` closure, so calls on unrelated receivers (e.g. the
  # `package:http` client's `http.get(url)`) are never mistaken for routes.
  #
  # Not yet handled: reflection-based `@Expose` controller classes and the
  # `chain([...]).<verb>(...)` form where the verb is called directly on a
  # `chain(...)` result rather than a bound router variable.
  class Angel3 < Analyzer
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

    # A `group('/prefix', (router) { ... })` block: its composed prefix,
    # the child-router parameter name, and the char range of its closure
    # body (where calls on `param` are scoped to this group).
    alias Group = NamedTuple(prefix: String, param: String, range_start: Int32, range_end: Int32)
    # Raw group before prefix composition (also carries the call offset so
    # the enclosing group can be resolved).
    alias RawGroup = NamedTuple(own: String, param: String, range_start: Int32, range_end: Int32, call: Int32)

    # Receiver `.verb(` calls; `(?<![\w$.])` keeps the receiver to a single
    # identifier so `chain([...]).post(` (receiver is a `)`) is skipped.
    CALL_REGEX = /(?<![\w$.])([A-Za-z_]\w*)\s*\.\s*([a-zA-Z]+)\s*\(/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      result = [] of Endpoint
      mutex = Mutex.new

      begin
        files = get_files_by_extension(".dart")

        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")
          next if Helper.test_path?(path, base_paths)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          next unless angel_file?(content)

          endpoints = scan_file(content, path, include_callee)
          next if endpoints.empty?

          mutex.synchronize { result.concat(endpoints) }
        end
      rescue e
        logger.debug e
      end

      result
    end

    private def angel_file?(content : String) : Bool
      content.includes?("package:angel3_framework/") ||
        content.includes?("package:angel_framework/") ||
        content.includes?("Angel(")
    end

    private def scan_file(content : String, path : String, include_callee : Bool) : Array(Endpoint)
      cleaned = Helper.strip_comments(content)
      groups = collect_groups(cleaned)
      top_vars = angel_router_vars(cleaned)
      group_params = groups.map(&.[:param]).to_set
      return [] of Endpoint if top_vars.empty? && groups.empty?

      endpoints = [] of Endpoint
      seen = Set({String, String}).new

      cleaned.scan(CALL_REGEX) do |m|
        var = m[1]
        method = m[2]
        next unless relevant_method?(method)
        next unless top_vars.includes?(var) || group_params.includes?(var)

        offset = m.begin(0)
        next unless offset
        prefix = prefix_for(var, offset, groups, top_vars)
        next if prefix.nil?

        open_paren = (m.end(0) || 0) - 1
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren

        handle_call(method, cleaned, open_paren, close_paren, prefix, content, path, include_callee, endpoints, seen)
      end

      endpoints
    end

    # The composed prefix a route on `var` at `offset` should carry:
    # the innermost enclosing `group` whose closure parameter is `var`,
    # else "" when `var` is a top-level `Angel` instance.
    private def prefix_for(var : String, offset : Int32, groups : Array(Group), top_vars : Set(String)) : String?
      best = nil.as(Group?)
      best_size = Int32::MAX
      groups.each do |g|
        next unless g[:param] == var
        next unless offset >= g[:range_start] && offset <= g[:range_end]
        size = g[:range_end] - g[:range_start]
        if size < best_size
          best = g
          best_size = size
        end
      end
      return best[:prefix] if best
      return "" if top_vars.includes?(var)
      nil
    end

    private def relevant_method?(name : String) : Bool
      HTTP_METHOD_MAP.has_key?(name) || name == "all"
    end

    # Variables holding an `Angel()` instance, plus parameters/fields typed
    # `Angel` (so `Future configureServer(Angel app)` is picked up too).
    ANGEL_ASSIGN_REGEX = /(?:^|[;{}=(,\s])(?:final|var|const|late)\s+(?:Angel\s+)?([A-Za-z_]\w*)\s*=\s*(?:await\s+)?Angel\s*\(/
    ANGEL_TYPED_REGEX  = /(?:^|[;{}(,])\s*Angel\s+([A-Za-z_]\w*)/

    private def angel_router_vars(cleaned : String) : Set(String)
      vars = Set(String).new
      cleaned.scan(ANGEL_ASSIGN_REGEX) do |m|
        name = m[1]
        vars << name unless name.empty?
      end
      cleaned.scan(ANGEL_TYPED_REGEX) do |m|
        name = m[1]
        vars << name unless name.empty?
      end
      vars
    end

    # ---------- group() prefix composition ----------

    GROUP_REGEX = /\.group\s*\(/

    private def collect_groups(cleaned : String) : Array(Group)
      raw = [] of RawGroup
      cleaned.scan(GROUP_REGEX) do |m|
        call = m.begin(0)
        open_paren = (m.end(0) || 0) - 1
        next unless call
        close_paren = find_matching_paren(cleaned, open_paren)
        next unless close_paren
        args = split_top_level_args(cleaned[(open_paren + 1)...close_paren])
        next if args.size < 2

        literal = Helper.extract_string_literal(args[0])
        next unless literal
        param = closure_param(args[1])
        next unless param

        comma = first_top_level_comma(cleaned, open_paren + 1, close_paren)
        next unless comma
        raw << {own: normalize_path(literal), param: param, range_start: comma + 1, range_end: close_paren, call: call}
      end

      raw.map do |g|
        {prefix: composed_prefix(g, raw), param: g[:param], range_start: g[:range_start], range_end: g[:range_end]}
      end
    end

    # Walk up the chain of enclosing groups (a group's `.group(` call sits
    # inside its parent's closure range) to build the full nested prefix.
    private def composed_prefix(group : RawGroup, raw : Array(RawGroup)) : String
      prefix = group[:own]
      current = group
      visited = Set(Int32).new
      loop do
        break unless visited.add?(current[:call])
        parent = enclosing_group(current, raw)
        break unless parent
        prefix = join_path(parent[:own], prefix)
        current = parent
      end
      prefix
    end

    private def enclosing_group(group : RawGroup, raw : Array(RawGroup)) : RawGroup?
      best = nil.as(RawGroup?)
      best_size = Int32::MAX
      raw.each do |candidate|
        next if candidate[:call] == group[:call]
        next unless group[:call] >= candidate[:range_start] && group[:call] <= candidate[:range_end]
        size = candidate[:range_end] - candidate[:range_start]
        if size < best_size
          best = candidate
          best_size = size
        end
      end
      best
    end

    # The child-router parameter name of a `group` closure argument
    # (`(router) { ... }` or `(router) => ...`).
    private def closure_param(arg : String) : String?
      stripped = arg.strip
      return unless stripped.starts_with?('(')
      if m = stripped.match(/\A\(\s*([A-Za-z_]\w*)/)
        return m[1]
      end
      nil
    end

    # ---------- endpoint construction ----------

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
      args = split_top_level_args(source[(open_paren + 1)...close_paren])
      return if args.size < 2

      literal = Helper.extract_string_literal(args[0])
      return unless literal

      url = join_path(prefix, normalize_path(literal))
      line = line_for_offset(content, open_paren)

      callees = [] of Noir::DartCalleeExtractor::Entry
      if include_callee
        comma = first_top_level_comma(source, open_paren + 1, close_paren)
        callees = handler_callees(args[1], content, comma + 1, path, line) if comma
      end

      verbs = method == "all" ? ALL_VERBS : [HTTP_METHOD_MAP[method]]
      verbs.each do |verb|
        next unless seen.add?({verb, url})
        endpoints << build_endpoint(url, verb, path, line, callees)
      end
    end

    HANDLER_REFERENCE_REGEX = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/

    private def handler_callees(handler_arg : String,
                                content : String,
                                handler_start : Int32,
                                path : String,
                                line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      stripped = handler_arg.strip

      unless stripped.starts_with?('(')
        return [] of Noir::DartCalleeExtractor::Entry unless stripped.matches?(HANDLER_REFERENCE_REGEX)
        return [{stripped, path, line}] of Noir::DartCalleeExtractor::Entry
      end

      start_b = content.char_index_to_byte_index(handler_start)
      return [] of Noir::DartCalleeExtractor::Entry unless start_b
      body_info = Noir::DartCalleeExtractor.extract_body_after(content, start_b)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    # Ensure a leading slash and translate Express-style `:id` captures
    # into `{id}` path params. A trailing `?` (optional, `:arg?`) is dropped.
    private def normalize_path(path : String) : String
      base = path.starts_with?('/') ? path : "/#{path}"
      base.gsub(/:([A-Za-z_]\w*)\??/) { "{#{$~[1]}}" }
    end

    private def join_path(prefix : String, sub : String) : String
      return sub if prefix.empty?
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

    # ---------- source-string utilities ----------

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
