require "../../engines/python_engine"

module Analyzer::Python
  # Starlette's path syntax and the request reads in a Starlette endpoint
  # body, shared by every adapter whose handlers are Starlette endpoints
  # (Starlette itself, FastMCP's `custom_route`).
  module StarletteEndpointSupport
    # Path param in a route pattern: {name} or {name:type}. Starlette uses
    # the :type suffix as a converter hint (int, str, float, uuid, path);
    # it is stripped before the param is exposed as a path param.
    PATH_PARAM_REGEX       = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*):[a-zA-Z_][a-zA-Z0-9_]*\}/

    # Request-access matchers interpolate a discovered request-var name
    # (`request`, `self.request`, ...) so they can't be class constants,
    # but a handler set only uses a handful of distinct names — memoize
    # the compiled set per name instead of rebuilding it on every line
    # of every handler body.
    private record AwaitBodyRegexes,
      json_await : Regex,
      form_await : Regex,
      json_assign : Regex,
      form_assign : Regex

    @await_body_regex_cache = Hash(::String, AwaitBodyRegexes).new
    @attr_regex_cache = Hash(Tuple(::String, ::String), Tuple(Regex, Regex)).new
    @body_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    private def await_body_regexes(request_name : ::String) : AwaitBodyRegexes
      @await_body_regex_cache[request_name] ||= begin
        rp = Regex.escape(request_name)
        AwaitBodyRegexes.new(
          json_await: /await\s+#{rp}\.json\s*\(/,
          form_await: /await\s+#{rp}\.form\s*\(/,
          json_assign: /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{rp}\.json\s*\(/,
          form_assign: /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{rp}\.form\s*\(/,
        )
      end
    end

    private def normalize_route_url(prefix : ::String, route_path : ::String) : ::String
      full_url = "#{prefix}#{route_path}"
      full_url = "/#{full_url}".gsub(/\/+/, "/")
      full_url = full_url.gsub("{{", "{").gsub("}}", "}")
      # `{p:path}` stays: it spans `/`, so it is not `{p}`.
      full_url.gsub(TYPED_PATH_PARAM_REGEX) { |typed| typed.ends_with?(":path}") ? typed : "{#{$~[1]}}" }
    end

    private def extract_path_params(route_path : ::String) : Array(Param)
      params = [] of Param
      unescaped = route_path.gsub("{{", "{").gsub("}}", "}")
      unescaped.scan(PATH_PARAM_REGEX) do |match|
        name = match[1]
        next if params.any? { |p| p.name == name }
        params << Param.new(name, "", "path")
      end
      params
    end

    private def extract_request_arg_name(args : ::String) : ::String?
      names = args.split(",").map do |arg|
        arg.split("=", 2)[0].split(":", 2)[0].strip
      end.reject(&.empty?)
      names.find { |name| name != "self" && name != "cls" }
    end

    # The params and callees of the function endpoint `def <name>(<request_name>, ...)`
    # at `def_line`.
    private def starlette_handler_context(lines : Array(::String),
                                          def_line : Int32,
                                          request_name : ::String,
                                          path : ::String,
                                          *,
                                          definition_base_path : ::String,
                                          source : ::String) : Tuple(Array(Param), Array(Callee))
      params = [] of Param
      codeblock = parse_code_block(lines[def_line..])
      return {params, [] of Callee} if codeblock.nil?

      request_body_res = await_body_regexes(request_name)
      fold_python_continuations(codeblock.split("\n")).each do |cl|
        collect_websocket_params(cl, request_name, params)

        if cl.matches?(request_body_res.json_await)
          add_unique(params, Param.new("body", "", "json"))
        end
        if cl.matches?(request_body_res.form_await)
          add_unique(params, Param.new("body", "", "form"))
        end
      end
      collect_request_body_params(codeblock, request_name, params)

      callees = build_callees_from(codeblock, def_line, path,
        definition_base_path: definition_base_path, source: source)
      {params, callees}
    end

    private def collect_websocket_params(source : ::String, request_name : ::String, params : Array(Param))
      fold_python_continuations(source.lines).each do |line|
        collect_request_attr_params(line, request_name, "path_params", "path", params)
        collect_request_attr_params(line, request_name, "query_params", "query", params)
        collect_request_attr_params(line, request_name, "headers", "header", params)
        collect_request_attr_params(line, request_name, "cookies", "cookie", params)
      end
    end

    private def request_attr_regexes(request_name : ::String, attr : ::String) : Tuple(Regex, Regex)
      @attr_regex_cache[{request_name, attr}] ||= begin
        rp = Regex.escape(request_name)
        # `.get(` and `.getlist(`: Starlette's QueryParams / Headers are
        # multidicts exposing `getlist("key")` for repeated keys, reading
        # the same first-arg key as `get`.
        {/#{rp}\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
         /#{rp}\.#{attr}\.get(?:list)?\(\s*[rf]?['"]([^'"]+)['"]/}
      end
    end

    private def collect_request_attr_params(line : ::String, request_name : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      # The attr substring is a necessary condition for either pattern,
      # so most lines skip the regex matches entirely.
      return unless line.includes?(attr)
      bracket_re, get_re = request_attr_regexes(request_name, attr)
      line.scan(bracket_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(get_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def body_var_regexes(var : ::String) : Tuple(Regex, Regex)
      @body_var_regex_cache[var] ||= begin
        v = Regex.escape(var)
        {/(?:^|[^a-zA-Z0-9_])#{v}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
         /(?:^|[^a-zA-Z0-9_])#{v}\.get\(\s*[rf]?['"]([^'"]+)['"]/}
      end
    end

    private def collect_request_body_params(codeblock : ::String, request_name : ::String, params : Array(Param))
      request_body_res = await_body_regexes(request_name)
      { {"json", request_body_res.json_assign}, {"form", request_body_res.form_assign} }.each do |noir_type, assign_re|
        body_vars = [] of ::String
        codeblock.scan(assign_re) do |m|
          body_vars << m[1]
        end

        body_vars.each do |var|
          bracket_re, get_re = body_var_regexes(var)
          codeblock.scan(bracket_re) do |m|
            add_unique(params, Param.new(m[1], "", noir_type))
          end
          codeblock.scan(get_re) do |m|
            add_unique(params, Param.new(m[1], "", noir_type))
          end
        end
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
