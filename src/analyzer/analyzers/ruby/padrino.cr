require "../../engines/ruby_engine"

module Analyzer::Ruby
  # Padrino layers two things on top of Sinatra's route table:
  #
  #   1. Named, block-scoped routes declared through the controller DSL —
  #      `AppName.controllers :posts do get :index, map: '/blog' do ... end
  #      end` — where the effective URL is derived from the controller
  #      name, the route name, and the optional `map:`/`with:`/`parent:`
  #      options rather than a literal path string.
  #   2. Base-path mounting of each sub-app from `config/apps.rb` —
  #      `Padrino.mount('blog', app_class: 'BlogApp').to('/blog')` — which
  #      every route inside that sub-app inherits as a prefix.
  #
  # `ruby_padrino` supersedes `ruby_sinatra` (see the catalog entry), so this
  # analyzer also re-implements Sinatra's own literal-path route matching
  # (`get "/path" do`, `namespace "/x" do`) via the shared `RubyEngine`
  # helpers — when both techs are detected, the Sinatra analyzer does not
  # run at all, and nothing may be lost by dropping it.
  class Padrino < RubyEngine
    analyzer_for "ruby_padrino"

    # Precompile the `<verb> :name` matchers once — same reasoning as
    # `RubyEngine::VERB_ROUTE_PATTERNS` (interpolated regex literals are
    # recompiled on every evaluation otherwise). Group 1 is the route name,
    # group 2 is everything after it on the line (options + block opener).
    SYMBOL_VERB_PATTERNS = HTTP_VERBS.map do |verb|
      {verb, /^#{verb}\s*\(?\s*:(\w+)\b(.*)$/}
    end

    # `map:`/`:map =>`, `with:`/`:with =>`, `parent:`/`:parent =>` — Padrino
    # apps span enough Ruby-version history that both hash syntaxes show up
    # in real projects.
    MAP_OPTION_RE    = /(?::map\s*=>|map:)\s*['"]([^'"]+)['"]/
    WITH_OPTION_RE   = /(?::with\s*=>|with:)\s*(\[[^\]]*\]|:[\w]+)/
    PARENT_OPTION_RE = /(?::parent\s*=>|parent:)\s*:?['"]?(\w+)/

    # `<Receiver>.controllers :name do` / `controllers :name do` (no
    # receiver, called inside the app class body) / `controllers "/admin"
    # do` (explicit string prefix) / bare `controller do` (grouping only,
    # no prefix). Group 1 is the argument list between the keyword and the
    # block opener.
    CONTROLLER_OPEN_RE = /^(?:[\w:]+\s*\.\s*)?controllers?\b(.*?)(?:\bdo\b|\{)/

    # `class BlogApp < Padrino::Application` — opens an (empty-prefix)
    # controller scope so a bare `get :index do` written directly in the
    # app class body (no enclosing `controllers` block) still resolves.
    CLASS_APP_RE = /\bclass\s+([\w:]+)\s*<\s*Padrino::Application\b/

    NAMESPACE_OPEN_RE = /^namespace\s*\(?\s*['"]([^'"]+)['"]\s*\)?\s*(?:do\b|\{)/

    # `Padrino.mount('blog', app_class: 'BlogApp').to('/blog')` — matched
    # per-line (mount declarations are always a single statement in every
    # real-world `config/apps.rb`), so a `[^)]*` options capture never has
    # to worry about matching past the end of the file.
    MOUNT_LINE_RE    = /Padrino\.mount\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*(.*?))?\)\s*\.to\(\s*['"]([^'"]*)['"]\s*\)/
    APP_CLASS_OPT_RE = /(?::app_class\s*=>|app_class:)\s*['"]([^'"]+)['"]/

    def analyze
      include_callee = callees_needed?
      mount_prefixes = build_mount_prefixes

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        next if ruby_non_production_path?(path)
        content = read_file_content(path)
        # Same rationale as the Sinatra analyzer: a Rails/Hanami route
        # table is never also a Padrino app's route file.
        next if rails_router_source?(content) || hanami_router_source?(content)

        mount_prefix = file_mount_prefix(content, mount_prefixes)
        analyze_file(path, content, mount_prefix, include_callee)
      end

      @result
    end

    private def analyze_file(path : String, content : String, mount_prefix : String, include_callee : Bool)
      lines = content.each_line.to_a
      active_route_endpoints = [] of Endpoint
      active_route_depth = nil.as(Int32?)
      prefix_stack = [] of NamedTuple(depth: Int32, path: String)
      depth = 0

      lines.each_with_index do |line, index|
        next unless line.valid_encoding?
        stripped = Noir::RubyCalleeExtractor.strip_comment(line, preserve_strings: true).strip
        next if stripped.empty? || stripped.starts_with?('#')

        line_delta = padrino_depth_delta(line)

        if ns = stripped.match(NAMESPACE_OPEN_RE)
          prefix_stack << {depth: depth + 1, path: ns[1]}
        elsif cm = stripped.match(CONTROLLER_OPEN_RE)
          prefix_stack << {depth: depth + 1, path: controller_segment(cm[1]? || "")}
        elsif stripped.match(CLASS_APP_RE)
          prefix_stack << {depth: depth + 1, path: ""}
        end

        route_endpoints = line_to_endpoints(stripped, prefix_stack)
        unless route_endpoints.empty?
          route_endpoints.each do |endpoint|
            endpoint.url = apply_mount_prefix(mount_prefix, endpoint.url)
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint.details = details
            attach_route_callees(endpoint, lines, index, path) if include_callee
            @result << endpoint
          end

          if line_delta > 0
            active_route_endpoints = route_endpoints
            active_route_depth = depth + 1
          else
            active_route_endpoints = [] of Endpoint
            active_route_depth = nil
          end
        end

        line_to_params(stripped).each do |param|
          target_endpoints = if route_endpoints.empty?
                               if (route_depth = active_route_depth) && !active_route_endpoints.empty? && depth >= route_depth
                                 active_route_endpoints
                               else
                                 [] of Endpoint
                               end
                             else
                               route_endpoints
                             end

          target_endpoints.each(&.push_param(param))
        end

        depth += line_delta
        while !prefix_stack.empty? && prefix_stack.last[:depth] > depth
          prefix_stack.pop
        end
        if (route_depth = active_route_depth) && depth < route_depth
          active_route_endpoints = [] of Endpoint
          active_route_depth = nil
        end
      end
    end

    private def line_to_endpoints(content : String, prefix_stack : Array(NamedTuple(depth: Int32, path: String))) : Array(Endpoint)
      leading = content.lstrip

      SYMBOL_VERB_PATTERNS.each do |verb, pattern|
        next unless leading.starts_with?(verb)
        next if leading.size > verb.size && (leading[verb.size].alphanumeric? || leading[verb.size] == '_')

        if m = leading.match(pattern)
          return [build_symbol_endpoint(verb, m[1], m[2]? || "", prefix_stack)]
        end
      end

      # Literal-path routes (`get "/path" do`) are Sinatra's own DSL,
      # unchanged under Padrino — reuse `RubyEngine#line_to_endpoint`
      # rather than re-deriving the same matcher.
      endpoint = line_to_endpoint(content)
      return [] of Endpoint if endpoint.method.empty?

      endpoint.url = padrino_prefixed_path(prefix_stack, endpoint.url)
      [endpoint]
    end

    private def build_symbol_endpoint(verb : String, route_name : String, rest : String, prefix_stack : Array(NamedTuple(depth: Int32, path: String))) : Endpoint
      local_path =
        if mm = rest.match(MAP_OPTION_RE)
          map_value = mm[1]
          map_value.starts_with?('/') ? map_value : "/#{map_value}"
        else
          segments = collect_stack_segments(prefix_stack)
          segments << route_name unless route_name == "index"
          if wm = rest.match(WITH_OPTION_RE)
            wm[1].scan(/:(\w+)/) { |sm| segments << ":#{sm[1]}" }
          end
          segments.empty? ? "/" : "/#{segments.join("/")}"
        end

      Endpoint.new(local_path, verb.upcase)
    end

    # `parent: :user` (or `:parent => :user`) prepends `user/:user_id`
    # ahead of the controller's own name segment — matches
    # `url_for(:product, :index, user_id: 5) => "/user/5/product"` from the
    # Padrino routing guide.
    private def controller_segment(args : String) : String
      segments = [] of String

      if pm = args.match(PARENT_OPTION_RE)
        parent = pm[1]
        segments << parent << ":#{parent}_id"
      end

      if am = args.match(/\A\s*:(\w+)/)
        segments << am[1]
      elsif am = args.match(/\A\s*['"]([^'"]*)['"]/)
        am[1].split("/").each { |piece| segments << piece unless piece.strip.empty? }
      end

      segments.join("/")
    end

    private def collect_stack_segments(prefix_stack : Array(NamedTuple(depth: Int32, path: String))) : Array(String)
      segments = [] of String
      prefix_stack.each { |entry| append_padrino_path(segments, entry[:path]) }
      segments
    end

    private def padrino_prefixed_path(prefix_stack : Array(NamedTuple(depth: Int32, path: String)), path : String) : String
      segments = collect_stack_segments(prefix_stack)
      append_padrino_path(segments, path)
      segments.empty? ? "/" : "/#{segments.join("/")}"
    end

    private def append_padrino_path(segments : Array(String), raw : String)
      raw.split("/").each do |piece|
        trimmed = piece.strip
        segments << trimmed unless trimmed.empty?
      end
    end

    private def apply_mount_prefix(mount_prefix : String, local_path : String) : String
      return local_path if mount_prefix.empty?

      suffix = local_path == "/" ? "" : local_path
      combined = "#{mount_prefix}#{suffix}"
      combined.empty? ? "/" : combined
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_ruby_do_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    # Same params surface as Sinatra: `params[...]`/`params.fetch(...)` as
    # query params, `request.env[...]`/`headers[...]` as headers,
    # `cookies[...]` as cookies. `splat`/`captures` are Sinatra's own
    # pattern bindings, not user-supplied fields.
    PADRINO_RESERVED_PARAMS = Set{"splat", "captures"}

    private def line_to_params(content : String) : Array(Param)
      params = [] of Param
      return params unless content.includes?('[') || content.includes?("fetch")

      content.scan(/params\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty? || PADRINO_RESERVED_PARAMS.includes?(name)
      end

      content.scan(/params\.fetch\s*\(\s*(?::(\w+)|['"]([^'"]+)['"])/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty?
      end

      content.scan(/request\.env\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        name = m[1].strip
        params << Param.new(name, "", "header") unless name.empty?
      end

      content.scan(/headers\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "header") unless name.empty?
      end

      content.scan(/cookies\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "cookie") unless name.empty?
      end

      params
    end

    # Same block-nesting delta as the Sinatra analyzer (see its
    # `SINATRA_DEPTH_TOKEN_RE` for the detailed rationale) — duplicated
    # rather than shared so this analyzer stays self-contained.
    PADRINO_DEPTH_TOKEN_RE = /\bend\b|\bdo\b|(?:^|;)\s*(?:if|unless|case|begin|while|until|for|class|module|def)\b/

    private def padrino_depth_delta(line : String) : Int32
      structure = Noir::RubyCalleeExtractor.strip_comment(line, preserve_strings: false)
      delta = structure.count('{') - structure.count('}')
      structure.scan(PADRINO_DEPTH_TOKEN_RE) do |m|
        delta += m[0] == "end" ? -1 : 1
      end
      delta
    end

    # Builds the app-identifier -> mount-prefix map from every
    # `Padrino.mount(...).to('/prefix')` call in the project (conventionally
    # `config/apps.rb`, but not assumed to live there). Keys the prefix
    # under the mount name itself, a camelized version of it (Padrino's
    # default `app_class` when none is given), and the explicit
    # `app_class:`/`:app_class =>` value when present.
    private def build_mount_prefixes : Hash(String, String)
      prefixes = {} of String => String

      get_files_by_extensions(RUBY_SOURCE_EXTENSIONS).each do |path|
        next if ruby_non_production_path?(path)
        content = read_file_content(path)
        next unless content.includes?("Padrino.mount")

        content.each_line do |line|
          next unless m = line.match(MOUNT_LINE_RE)

          name = m[1].strip
          prefix = normalize_padrino_mount_prefix(m[3])
          keys = [name, camelize_padrino(name)]

          if (opts = m[2]?) && (am = opts.match(APP_CLASS_OPT_RE))
            keys << am[1]
          end

          keys.uniq.each do |key|
            next if key.empty?
            prefixes[key] ||= prefix
          end
        end
      end

      prefixes
    end

    # Resolves the file's own mount prefix by looking up either the
    # `Padrino::Application` subclass declared in it, or the receiver of
    # the first `.controllers` call (for a controller file that references
    # its app class explicitly instead of being nested inside it).
    private def file_mount_prefix(content : String, mount_prefixes : Hash(String, String)) : String
      return "" if mount_prefixes.empty?

      if m = content.match(CLASS_APP_RE)
        prefix = lookup_mount_prefix(mount_prefixes, m[1])
        return prefix unless prefix.empty?
      end

      if m = content.match(/([\w:]+)\s*\.\s*controllers?\b/)
        return lookup_mount_prefix(mount_prefixes, m[1])
      end

      ""
    end

    private def lookup_mount_prefix(mount_prefixes : Hash(String, String), key : String) : String
      parts = key.split("::")
      candidates = parts.size > 1 ? [key, parts.first, parts.last] : [key]
      candidates.each do |candidate|
        if prefix = mount_prefixes[candidate]?
          return prefix
        end
      end
      ""
    end

    private def normalize_padrino_mount_prefix(raw : String) : String
      trimmed = raw.strip
      return "" if trimmed.empty? || trimmed == "/"

      trimmed = "/#{trimmed}" unless trimmed.starts_with?('/')
      trimmed.rstrip("/")
    end

    private def camelize_padrino(name : String) : String
      name.split(/[_\-]/).reject(&.empty?).map do |part|
        part.size > 1 ? "#{part[0].upcase}#{part[1..]}" : part.upcase
      end.join
    end
  end
end
