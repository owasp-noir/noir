require "../../engines/python_engine"

module Analyzer::Python
  # Reference: https://docs.masoniteproject.com/features/routing
  #
  # Masonite (current v4/v5 API) routes live in `routes/web.py` (and
  # sibling `routes/*.py` modules such as `routes/api.py`) as a plain
  # list assigned to `ROUTES`, built from classmethods on
  # `masonite.routes.Route`:
  #
  #   Route.get/post/put/patch/delete/options(url, controller, **opts)
  #   Route.any(url, controller)                    -> all six verbs
  #   Route.match([methods], url, controller)
  #   Route.group([...routes...], prefix=, middleware=, name=, domain=)
  #   Route.resource(base_url, controller)           -> 7 REST routes
  #   Route.api(base_url, controller)                -> 5 REST-API routes
  #   Route.view(url, template, data)                -> GET, no controller
  #   Route.redirect/permanent_redirect(url, new)    -> GET, no controller
  #
  # `controller` is either the documented string binding
  # (`'WelcomeController@show'`, defaulting to `__call__` with no `@`)
  # or a direct class/method reference (`WelcomeController.show`) — both
  # are handled. `Route.fallback(...)` (a catch-all with no concrete
  # path) and route `.name(...)`/`.domain(...)` are intentionally not
  # modeled — they carry no attack-surface information Noir tracks.
  #
  # NOTE — Masonite ≤3 used a different, now-legacy routing API: bare
  # `Get`/`Post`/`RouteGroup` classes imported directly from
  # `masonite.routes` (e.g. `Get('/x', 'C@m')`,
  # `RouteGroup([...], prefix=...)`) with controllers resolved under
  # `app/http/controllers`. That shape is NOT handled here; this
  # analyzer targets the current `Route.*` DSL used by the official
  # project skeleton (MasoniteFramework/cookie-cutter, `app/controllers`)
  # and current docs. A legacy-style project still gets detected as
  # Masonite (the detector only looks for `masonite` imports) but yields
  # no routes from this analyzer.
  class Masonite < PythonEngine
    analyzer_for "python_masonite"

    HTTP_VERB_METHODS = {
      "get"     => ["GET"],
      "post"    => ["POST"],
      "put"     => ["PUT"],
      "patch"   => ["PATCH"],
      "delete"  => ["DELETE"],
      "options" => ["OPTIONS"],
    }
    ANY_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    # Verbs recognized while scanning `Route.<verb>(...)` call sites.
    # Anything else (`.compile`, `.set_controller_locations`,
    # `.fallback`, `.default`, ...) is deliberately left unmatched.
    ROUTE_CALL_VERBS = Set{
      "get", "post", "put", "patch", "delete", "options",
      "any", "match", "group", "resource", "api", "view",
      "redirect", "permanent_redirect",
    }

    # `Route.resource(base_url, controller)` — see
    # `masonite.routes.Route.resource`: seven conventional REST routes.
    RESOURCE_ACTIONS = [
      {["GET"], "", "index"},
      {["GET"], "/create", "create"},
      {["POST"], "", "store"},
      {["GET"], "/@id", "show"},
      {["GET"], "/@id/edit", "edit"},
      {["PUT", "PATCH"], "/@id", "update"},
      {["DELETE"], "/@id", "destroy"},
    ]

    # `Route.api(base_url, controller)` — API-style subset (no
    # create/edit HTML forms).
    API_RESOURCE_ACTIONS = [
      {["GET"], "", "index"},
      {["POST"], "", "store"},
      {["GET"], "/@id", "show"},
      {["PUT", "PATCH"], "/@id", "update"},
      {["DELETE"], "/@id", "destroy"},
    ]

    @masonite_base_path : ::String = ""
    @controller_file_cache = Hash(::String, ::String?).new

    def analyze
      endpoints = [] of Endpoint

      masonite_route_files.each do |file, base_path|
        @masonite_base_path = base_path
        content = read_file_content(file)
        extract_route_endpoints(content, file).each { |endpoint| endpoints << endpoint }
      end

      extract_static_endpoints.each { |endpoint| endpoints << endpoint }

      endpoints
    end

    # `routes/*.py` files that actually pull in Masonite's routing DSL —
    # scoped this way (directory convention + a genuine import signal +
    # actual `Route.` usage) so a same-named `routes/web.py` belonging to
    # a different framework in the same repo/monorepo is never touched.
    private def masonite_route_files : Array({::String, ::String})
      files = [] of {::String, ::String}

      python_source_files.each do |file|
        relative = base_relative_path(file)
        next unless relative.includes?("/routes/") || relative.starts_with?("routes/")

        content = read_file_content(file)
        next unless content.matches?(/\bfrom\s+masonite(\.routes)?\s+import\b/) || content.matches?(/\bimport\s+masonite\.routes\b/)
        next unless content.includes?("Route.")

        files << {file, python_base_path_for(file)}
      end

      files
    end

    private def extract_route_endpoints(content : ::String, route_file : ::String) : Array(Endpoint)
      endpoints = [] of Endpoint
      calls = scan_route_calls(content)
      return endpoints if calls.empty?

      calls.each do |call|
        next if call.verb == "group" # groups only contribute a prefix to their children

        prefix = accumulated_prefix(call, calls)

        case call.verb
        when "get", "post", "put", "patch", "delete", "options"
          args = split_masonite_args(call.args)
          next if args.size < 2
          url = route_string_arg(args, 0, "url")
          next unless url
          endpoints.concat build_endpoints_for_route(prefix, url, HTTP_VERB_METHODS[call.verb], args[1]?, route_file, call.line)
        when "any"
          args = split_masonite_args(call.args)
          next if args.size < 2
          url = route_string_arg(args, 0, "url")
          next unless url
          endpoints.concat build_endpoints_for_route(prefix, url, ANY_METHODS, args[1]?, route_file, call.line)
        when "match"
          args = split_masonite_args(call.args)
          next if args.size < 3
          methods = args[0].scan(/[rf]?['"]([A-Za-z]+)['"]/).map(&.[1].upcase)
          next if methods.empty?
          url = route_string_arg(args, 1, "url")
          next unless url
          endpoints.concat build_endpoints_for_route(prefix, url, methods, args[2]?, route_file, call.line)
        when "resource"
          args = split_masonite_args(call.args)
          next if args.size < 2
          base = Helper.extract_python_string(args[0])
          controller = Helper.extract_python_string(args[1])
          next unless base && controller
          RESOURCE_ACTIONS.each do |(methods, suffix, action)|
            endpoints.concat build_endpoints_for_route(prefix, "#{base}#{suffix}", methods, "#{controller}@#{action}", route_file, call.line)
          end
        when "api"
          args = split_masonite_args(call.args)
          next if args.size < 2
          base = Helper.extract_python_string(args[0])
          controller = Helper.extract_python_string(args[1])
          next unless base && controller
          API_RESOURCE_ACTIONS.each do |(methods, suffix, action)|
            endpoints.concat build_endpoints_for_route(prefix, "#{base}#{suffix}", methods, "#{controller}@#{action}", route_file, call.line)
          end
        when "view"
          args = split_masonite_args(call.args)
          next if args.empty?
          url = route_string_arg(args, 0, "url")
          next unless url
          endpoints.concat build_endpoints_for_route(prefix, url, ["GET"], nil, route_file, call.line)
        when "redirect", "permanent_redirect"
          args = split_masonite_args(call.args)
          next if args.empty?
          url = route_string_arg(args, 0, "url")
          next unless url
          endpoints.concat build_endpoints_for_route(prefix, url, ["GET"], nil, route_file, call.line)
        end
      end

      endpoints
    end

    # `args[index]` as a plain string literal, falling back to a
    # `keyword=` spelling of the same positional slot (rare, but cheap
    # to support).
    private def route_string_arg(args : Array(::String), index : Int32, keyword : ::String) : ::String?
      arg = args[index]?
      return unless arg
      Helper.extract_python_string(arg) || begin
        if m = arg.strip.match(/\A#{Regex.escape(keyword)}\s*=\s*(.+)\z/m)
          Helper.extract_python_string(m[1])
        end
      end
    end

    private def build_endpoints_for_route(prefix : ::String,
                                          url : ::String,
                                          methods : Array(::String),
                                          controller_raw : ::String?,
                                          route_file : ::String,
                                          line : Int32) : Array(Endpoint)
      endpoints = [] of Endpoint
      full_url = normalize_masonite_path(Helper.normalized_join(prefix, url))
      path_params = masonite_path_params(url)
      resolved = controller_raw ? parse_controller_ref(controller_raw) : nil

      methods.each do |http_method|
        if resolved
          class_name, method_name = resolved
          if endpoint = build_endpoint_from_controller(full_url, http_method, class_name, method_name, path_params)
            endpoints << endpoint
            next
          end
        end

        details = Details.new(PathInfo.new(route_file, line))
        endpoint = Endpoint.new(full_url, http_method, [] of Param, details)
        path_params.each { |param| endpoint.push_param(param) }
        endpoints << endpoint
      end

      endpoints
    end

    private def build_endpoint_from_controller(url : ::String,
                                               http_method : ::String,
                                               class_name : ::String,
                                               method_name : ::String,
                                               path_params : Array(Param)) : Endpoint?
      filepath = find_controller_class_file(class_name, @masonite_base_path)
      return unless filepath

      content = read_file_content(filepath)
      class_start_index = content.index(/class\s+#{Regex.escape(class_name)}\s*[\(:]/)
      return unless class_start_index

      class_codeblock = parse_code_block(content[class_start_index..])
      return unless class_codeblock

      class_lines = class_codeblock.split("\n")
      def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(method_name)}\s*\(/
      def_offset = class_lines.index(&.matches?(def_re))
      return unless def_offset

      method_block = parse_code_block(class_lines[def_offset..])
      return unless method_block

      body_start_line = content[0, class_start_index].count('\n')
      definition_line = body_start_line + def_offset + 1

      details = Details.new(PathInfo.new(filepath, definition_line))
      endpoint = Endpoint.new(url, http_method, [] of Param, details)
      path_params.each { |param| endpoint.push_param(param) }
      extract_masonite_params(method_block).each { |param| endpoint.push_param(param) }

      build_callees_from(
        method_block,
        body_start_line + def_offset,
        filepath,
        definition_base_path: @masonite_base_path,
        source: content
      ).each { |callee| endpoint.push_callee(callee) }

      endpoint
    end

    # Resolve `'ControllerName@method'` / `'ns.ControllerName@method'`
    # (string binding, defaulting to `__call__` with no `@method`) or a
    # bare `ControllerName.method` / `ControllerName` reference (class
    # binding) into `{class_name, method_name}`.
    #
    # `raw` is either real Python source text (a quoted string literal or
    # a bare dotted expression) or the synthetic `"Name@action"` text
    # `extract_route_endpoints` builds for `Route.resource`/`Route.api`
    # expansion — already unquoted, so it's accepted as-is when it has
    # the same `Name@method` shape a quoted string would decode to.
    private def parse_controller_ref(raw : ::String) : Tuple(::String, ::String)?
      expr = raw.strip
      synthetic = expr.matches?(/\A[A-Za-z_][A-Za-z0-9_.]*@[A-Za-z_][A-Za-z0-9_]*\z/) ? expr : nil

      if str = Helper.extract_python_string(expr) || synthetic
        left, _, right = str.partition("@")
        class_name = left.split(".").last?
        return unless class_name
        return if class_name.empty?
        return {class_name, right.empty? ? "__call__" : right}
      end

      if m = expr.match(/\A([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?\z/)
        return {m[1], m[2]? || "__call__"}
      end

      nil
    end

    # Find the file defining `class <class_name>` — Masonite's own
    # resolution walks a configurable `controllers.location` (default
    # `app/controllers`), which Noir doesn't model as project
    # configuration; a project-wide class-name search is the practical
    # equivalent given every real Masonite project (including the
    # official skeleton) names the file after the class.
    #
    # `preferred_base` (the calling route file's own configured base
    # path) is ranked first so a multi-base scan of several independent
    # services never resolves service B's route to service A's
    # same-named controller — only falling back to a cross-base match
    # when nothing in the route's own base defines the class.
    private def find_controller_class_file(class_name : ::String, preferred_base : ::String) : ::String?
      cache_key = "#{preferred_base}::#{class_name}"
      return @controller_file_cache[cache_key] if @controller_file_cache.has_key?(cache_key)

      class_re = /^\s*class\s+#{Regex.escape(class_name)}\s*[\(:]/
      target_basename = "#{class_name}.py"

      candidates = python_source_files.select do |file|
        File.basename(file) == target_basename || base_relative_path(file).includes?("/controllers/")
      end
      candidates = python_source_files if candidates.empty?

      candidates.sort_by! do |file|
        {
          python_base_path_for(file) == preferred_base ? 0 : 1,
          File.basename(file) == target_basename ? 0 : 1,
          base_relative_path(file).includes?("/controllers/") ? 0 : 1,
          file,
        }
      end

      found = candidates.find do |file|
        read_file_content(file).each_line.any?(&.matches?(class_re))
      rescue
        false
      end

      @controller_file_cache[cache_key] = found
      found
    end

    # `request.param(...)` -> path, `request.input(...)`/`request.only(...)`
    # -> query (Masonite's `InputBag` merges the query string and the
    # POST/JSON body behind a single accessor, same ambiguity as Flask's
    # `request.values` — mirrored here with the same "query" bucket),
    # `request.cookie(...)` -> cookie, `request.header(...)` -> header.
    private def extract_masonite_params(body : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      body.scan(/\brequest\.input\(\s*[rf]?['"]([^'"]+)['"]/) { |m| record.call(m[1], "query") }
      body.scan(/\brequest\.param\(\s*[rf]?['"]([^'"]+)['"]/) { |m| record.call(m[1], "path") }
      body.scan(/\brequest\.cookie\(\s*[rf]?['"]([^'"]+)['"]/) { |m| record.call(m[1], "cookie") }
      body.scan(/\brequest\.header\(\s*[rf]?['"]([^'"]+)['"]/) { |m| record.call(m[1], "header") }
      body.scan(/\brequest\.only\(([^)]*)\)/) do |m|
        m[1].scan(/[rf]?['"]([^'"]+)['"]/) { |inner| record.call(inner[1], "query") }
      end

      params
    end

    # `@name` (required) / `?name` (optional) segments, each with an
    # optional `:compiler` suffix (`@id:integer`), are Masonite's path
    # parameters.
    private def masonite_path_params(url : ::String) : Array(Param)
      params = [] of Param
      url.split('/').each do |segment|
        next unless segment.starts_with?('@') || segment.starts_with?('?')
        name = segment[1..].split(':').first
        next if name.empty?
        params << Param.new(name, "", "path")
      end
      params
    end

    private def normalize_masonite_path(url : ::String) : ::String
      segments = url.split('/').map do |segment|
        if segment.starts_with?('@') || segment.starts_with?('?')
          "{#{segment[1..].split(':').first}}"
        else
          segment
        end
      end
      normalized = Helper.normalize_path(segments.join('/'))

      # Masonite strips a trailing slash from every compiled route except
      # the bare root (`HTTPRoute.__init__`) — a group whose inner route
      # is `"/"` (e.g. `Route.group([Route.get("/", ...)],
      # prefix="/admin/users")`) would otherwise serve `/admin/users`
      # but Noir would record `/admin/users/`.
      normalized.size > 1 && normalized.ends_with?("/") ? normalized[0..-2] : normalized
    end

    # Static assets — Masonite maps local directories to URL prefixes via
    # `STATICFILES` in `config/filesystem.py` (default skeleton ships
    # `"storage/static": "static/"`, `"storage/public": "/"`, ...).
    private def extract_static_endpoints : Array(Endpoint)
      endpoints = [] of Endpoint

      config_files = python_source_files.select do |file|
        File.basename(file) == "filesystem.py" && base_relative_path(file).includes?("config/")
      end

      config_files.each do |file|
        content = read_file_content(file)
        mappings = static_asset_mappings(content)
        next if mappings.empty?

        base = python_base_path_for(file)
        mappings.each do |local_dir, url_prefix|
          prefix = File.join(base, local_dir)
          prefix = "#{prefix}/" unless prefix.ends_with?("/")

          begin
            get_files_by_prefix(prefix).each do |asset_file|
              relative_path = asset_file.sub(prefix, "")
              endpoints << Endpoint.new(Helper.normalized_join(url_prefix, relative_path), "GET")
            end
          rescue e
            logger.debug e
          end
        end
      end

      endpoints
    end

    private def static_asset_mappings(content : ::String) : Array(Tuple(::String, ::String))
      mappings = [] of Tuple(::String, ::String)
      start = content.index(/\bSTATICFILES\s*=\s*\{/)
      return mappings unless start

      brace_index = content.index('{', start)
      return mappings unless brace_index

      close_index = matching_close(content, brace_index, '{', '}')
      return mappings unless close_index

      block = content[(brace_index + 1)...close_index]
      block.scan(/['"]([^'"]+)['"]\s*:\s*['"]([^'"]*)['"]/) do |m|
        mappings << {m[1], m[2]}
      end

      mappings
    end

    # ---- Route.* call-site scanning -----------------------------------

    private record MasoniteCall, verb : ::String, args : ::String, start_pos : Int32, end_pos : Int32, line : Int32

    # Flat scan for every `Route.<verb>(...)` call in the file (nested or
    # not — a call inside a `Route.group([...])` list is found here too,
    # at its own byte range). Nesting is later recovered from those byte
    # ranges in `accumulated_prefix`, which avoids needing a recursive
    # parse of the (possibly deeply nested) route-list literal.
    private def scan_route_calls(content : ::String) : Array(MasoniteCall)
      calls = [] of MasoniteCall

      content.scan(/\bRoute\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |m|
        verb = m[1]
        next unless ROUTE_CALL_VERBS.includes?(verb)

        open_index = m.end(0) - 1
        close_index = matching_close(content, open_index, '(', ')')
        next unless close_index

        args_text = content[(open_index + 1)...close_index]
        line = content[0, m.begin(0)].count('\n') + 1
        calls << MasoniteCall.new(verb, args_text, m.begin(0), close_index, line)
      end

      calls
    end

    # The nearest-enclosing `Route.group(...)` call's contributed prefix
    # chain, outermost first, joined into one normalized path prefix.
    private def accumulated_prefix(call : MasoniteCall, calls : Array(MasoniteCall)) : ::String
      chain = [] of ::String
      current = immediate_parent(call, calls)
      while current
        chain << group_prefix(current)
        current = immediate_parent(current, calls)
      end

      chain.reverse.reduce("") { |acc, part| Helper.normalized_join(acc, part) }
    end

    private def immediate_parent(call : MasoniteCall, calls : Array(MasoniteCall)) : MasoniteCall?
      enclosing = calls.select do |candidate|
        candidate.verb == "group" && candidate.start_pos < call.start_pos && candidate.end_pos > call.end_pos
      end
      return if enclosing.empty?

      enclosing.min_by { |candidate| candidate.end_pos - candidate.start_pos }
    end

    private def group_prefix(call : MasoniteCall) : ::String
      text = call.args
      list_open = text.index('[')
      list_close = list_open ? matching_close(text, list_open, '[', ']') : nil
      tail = list_close ? text[(list_close + 1)..] : text

      if m = tail.match(/\bprefix\s*=\s*[rf]?['"]([^'"]*)['"]/)
        m[1]
      else
        ""
      end
    end

    # Index of the delimiter matching `open_char` at `open_index`,
    # skipping delimiters inside single/double-quoted strings (with
    # backslash-escape tracking). Triple-quoted strings are not
    # modeled — route registration call sites never contain one.
    private def matching_close(text : ::String, open_index : Int32, open_char : Char, close_char : Char) : Int32?
      depth = 1
      i = open_index + 1
      in_quote : Char? = nil
      escaped = false

      while i < text.size
        ch = text[i]
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          i += 1
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
        when open_char
          depth += 1
        when close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end

      nil
    end

    # Top-level comma split honoring nested `()`/`[]`/`{}` and quotes.
    private def split_masonite_args(text : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_quote : Char? = nil
      escaped = false

      text.each_char do |ch|
        if in_quote
          current << ch
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
          current << ch
        when '('
          paren_depth += 1
          current << ch
        when ')'
          paren_depth -= 1 if paren_depth > 0
          current << ch
        when '['
          bracket_depth += 1
          current << ch
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
          current << ch
        when '{'
          brace_depth += 1
          current << ch
        when '}'
          brace_depth -= 1 if brace_depth > 0
          current << ch
        when ','
          if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end

      parts << current.to_s
      parts
    end
  end
end
