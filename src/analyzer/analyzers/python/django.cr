require "../../engines/python_engine"
require "json"
require "../../../utils/top_level_split"

module Analyzer::Python
  class Django < PythonEngine
    analyzer_for "python_django"

    # Base path for the Django project
    @django_base_path : ::String = ""
    @visited_url_paths = Hash(String, Bool).new
    @django_app_config_path_cache = Hash(::String, ::String).new
    @visited_app_config_paths = Set(::String).new

    # Regular expressions for extracting Django URL configurations
    REGEX_ROOT_URLCONF = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
    # The optional `(` admits the tuple form `include(("app.urls", "app"))`.
    REGEX_INCLUDE_URLS = /\binclude\s*\(\s*(?:\(\s*)?r?['"]([^'"\\]*)['"]/
    # `router = routers.DefaultRouter(trailing_slash=False)`
    DRF_SLASHLESS_ROUTER_RE = /\b([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=\s*[A-Za-z_][\w.]*Router\s*\([^)]*\btrailing_slash\s*=\s*False\b/
    # `http_method_names = ["get", "post"]` on a view class.
    DRF_TOKEN_VIEW_RE        = /\b(?:ObtainAuthToken|Token(?:ObtainPair|ObtainSliding|Refresh|RefreshSliding|Verify|Blacklist)View)\b/
    DRF_HTTP_METHOD_NAMES_RE = /^\s+http_method_names\s*=\s*[\[(]([^\])]*)[\])]/m

    # An auth decorator applied in the urlconf itself:
    # `path("saved/", login_required(SavedView.as_view()))`,
    # `permission_required("x")(view)`. The view file never shows it, so the
    # auth tagger (which reads decorators at the handler's line) cannot see
    # it; the analyzer tags the endpoint it builds from that pattern instead.
    URLCONF_AUTH_WRAPPER_RE = /\b(login_required|permission_required|staff_member_required|user_passes_test)\s*\(/
    TAGGER                  = "django_analyzer"

    # Verbs Django's own class-based views accept, for a urlconf that mounts
    # one directly (`auth_views.PasswordResetView.as_view()`): the class lives
    # in site-packages, outside the scan, so its body cannot be read.
    # `LogoutView` answered GET too below Django 5.
    DJANGO_BUILTIN_VIEW_METHODS = {
      "LoginView"                 => %w[GET POST],
      "LogoutView"                => %w[GET POST],
      "PasswordChangeView"        => %w[GET POST],
      "PasswordChangeDoneView"    => %w[GET],
      "PasswordResetView"         => %w[GET POST],
      "PasswordResetDoneView"     => %w[GET],
      "PasswordResetConfirmView"  => %w[GET POST],
      "PasswordResetCompleteView" => %w[GET],
      "TemplateView"              => %w[GET],
      "RedirectView"              => %w[GET],
    }

    # A module-level `X = get_class("search.views", "X")` or
    # `A, X = get_classes("m", ["A", "X"])` (Oscar's dynamic loader).
    VIEW_LOADER_BINDING_RE = /^(\([\w,\s]+\)|[\w, \t]+?)\s*=\s*get_class(?:es)?\(\s*['"]([\w.]+)['"]\s*,\s*([\[(][^\])]*[\])]|['"]\w+['"])/m

    # `def get(...)` / `async def post(...)` method heads in class-based
    # views. Precompiled — an interpolated literal would be recompiled on
    # every line of every CBV class body. Uses `HTTP_METHODS_EXCLUDING_QUERY`
    # (see `PythonEngine`): Django's CBV dispatch (`View.dispatch`) looks up
    # `request.method.lower()` against the class's `http_method_names`
    # allowlist, which does not include `query` upstream — unlike Flask's
    # duck-typed `getattr(self, request.method.lower())` dispatch, a
    # `def query(self):` method is genuinely inert unless a view manually
    # widens that allowlist, so matching it here would report a phantom
    # route.
    REGEX_CBV_METHOD_DEF = /\s+(?:async\s+)?def\s+(#{HTTP_METHODS_EXCLUDING_QUERY.join("|")})\s*\(/

    # HTTP_METHODS is a fixed table (from PythonEngine), so the
    # decorator-stack scan and the `request.method == "..."` scan below
    # (each an `.each` loop run per decorator line / per function-body
    # line) can look up a precompiled regex per method name instead of
    # interpolating and recompiling one on every iteration. Purely a
    # lookup-table hoist — the matched text/capture groups are unchanged,
    # so it doesn't affect the line/offset values computed elsewhere in
    # this file.
    #
    # `DECORATOR_METHOD_NAME_REGEXES` also uses `HTTP_METHODS_EXCLUDING_QUERY`,
    # for the OTHER reason that constant documents: it bare-word-matches a
    # method name anywhere in a decorator's text (this scan is not CBV-
    # specific — it runs over the decorator stack above a plain function
    # too), and real decorators (e.g. DRF-spectacular's
    # `OpenApiParameter("query", ...)`) commonly carry `query` as a
    # parameter name rather than a verb restriction.
    # `REQUEST_METHOD_NAME_REGEXES` keeps the full list: it only fires on
    # an explicit, quoted `request.method == "QUERY"` comparison, which is
    # unambiguous developer-written evidence, not a name collision.
    DECORATOR_METHOD_NAME_REGEXES = HTTP_METHODS_EXCLUDING_QUERY.to_h { |m| {m, /[^a-zA-Z0-9](#{m})[^a-zA-Z0-9]/} }
    REQUEST_METHOD_NAME_REGEXES   = HTTP_METHODS.to_h { |m| {m, /['"](#{m})['"]/} }

    # Map request parameters to their respective fields
    REQUEST_PARAM_FIELD_MAP = {
      "GET"          => {["GET"], "query"},
      "POST"         => {["POST"], "form"},
      "COOKIES"      => {nil, "cookie"},
      "META"         => {nil, "header"},
      "headers"      => {nil, "header"},
      "FILES"        => {["POST"], "form"},
      "data"         => {["POST", "PUT", "PATCH"], "form"},
      "query_params" => {nil, "query"},
    }

    # Precompiled per-field access patterns so `extract_params_from_line`
    # never rebuilds a PCRE2 regex per request field. Compiled once from
    # REQUEST_PARAM_FIELD_MAP. {field_name, field_methods, param_type,
    # bracket_re, get_re}
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELD_MAP.map do |field_name, tuple|
      {
        field_name,
        tuple[0],
        tuple[1],
        Regex.new("request\\.#{field_name}\\[[rf]?['\"]([^'\"]*)['\"]\\]"),
        # `.get(` and `.getlist(`: Django's QueryDict (`request.GET`,
        # `request.POST`) exposes `getlist("key")` for repeated keys
        # (`?tag=a&tag=b`), reading the same first-arg key as `get`.
        Regex.new("request\\.#{field_name}\\.get(?:list)?\\([rf]?['\"]([^'\"]*)['\"]"),
      }
    end

    # Map request parameter types to HTTP methods
    REQUEST_PARAM_TYPE_MAP = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH"],
      "cookie" => nil,
      "header" => nil,
    }

    def analyze
      endpoints = [] of Endpoint

      # Find root Django URL configurations
      root_django_urls_list = find_root_django_urls()
      root_django_urls_list.each do |root_django_urls|
        logger.debug "Found Django URL configurations in #{root_django_urls.filepath}"
        @django_base_path = root_django_urls.basepath
        extract_endpoints(root_django_urls).each do |endpoint|
          endpoints << endpoint
        end
      end

      # Scan `urls.py` modules the ROOT_URLCONF-anchored pass never
      # reached as routing roots of their own. Reusable Django apps and
      # libraries (Wagtail, DRF, …) — and any project scanned at the app
      # level — ship `urls.py` files with `urlpatterns` but no project
      # `settings.py` declaring `ROOT_URLCONF`, so the anchored pass
      # finds no root at all and the whole app silently maps to zero
      # endpoints.
      #
      # The same hole opens when a root urlconf DOES exist but builds
      # `urlpatterns` at import time instead of writing it out — for
      # example authentik's `authentik/root/urls.py`, which mounts every
      # app by looping over `get_apps()` and reading each app's
      # `mountpoint` attribute. Static analysis cannot follow that loop,
      # so the anchored pass returns only the handful of literal
      # `path()` entries beside it. That is a non-empty result, so
      # gating this pass on `endpoints.empty?` (as it used to be) made
      # every other `urls.py` in the tree unreachable: authentik's 81
      # urlconfs collapsed to three health/metrics routes. The loss was
      # invisible from the outside, too — pointing the scanner at any
      # one app directory reported that app's routes correctly, because
      # then there was no settings module above it to anchor to.
      #
      # So the pass always runs now. What keeps a module the anchored
      # pass already mounted from being reported a second time without
      # its prefix is `@visited_url_paths`, which `extract_endpoints`
      # fills in as it follows `include()` — a record of what was
      # actually resolved, not a guess about which URLs look alike.
      extract_endpoints_from_orphan_urlconfs.each do |endpoint|
        endpoints << endpoint
      end

      endpoints.concat(extract_channels_endpoints)

      endpoints
    end

    # Treat every unvisited, non-test `urls.py` (or `urls/` package
    # module) carrying a `urlpatterns` as its own routing root. Used
    # only for modules the ROOT_URLCONF anchor never reached, so the
    # paths are app-relative — there is no host project to supply a
    # mount prefix. `extract_endpoints` marks each file (and anything
    # it `include()`s) visited, so a module pulled in by another is
    # not processed twice.
    private def extract_endpoints_from_orphan_urlconfs : Array(Endpoint)
      endpoints = [] of Endpoint

      candidates = all_files.select do |file|
        next false unless file.ends_with?(".py")
        next false if base_relative_path(file).includes?("/site-packages/")
        next false if PythonEngine.python_test_path?(file, base_path_for(file))
        File.basename(file) == "urls.py" || file.includes?("/urls/")
      end

      # Shallower paths first so a parent urlconf is processed before
      # the modules it includes, keeping include() prefixes attached
      # to the more specific routes where a parent exists in-tree.
      candidates.sort_by! { |file| {file.count('/'), file} }

      # Dotted include() targets (`include("app.sub.urls")`) and
      # `from app.sub import urls` resolve against the scan root.
      # Dedup by canonical (expanded) path. `all_files` entries and the
      # paths `extract_endpoints` records when it follows an `include()`
      # can spell the same file differently (`./` prefix, trailing or
      # doubled slashes) depending on how the base path was passed, so a
      # plain string compare would re-process a module a parent urlconf
      # already pulled in — surfacing its routes a second time without
      # the include() prefix.
      visited = Set(::String).new
      @visited_url_paths.each_key { |key| visited << Noir::PathScope.expand(key) }

      candidates.each do |file|
        candidate_base_path = base_path_for(file)
        @django_base_path = candidate_base_path
        expanded = Noir::PathScope.expand(file)
        next if visited.includes?(expanded)
        begin
          content = read_file_content(file)
        rescue
          next
        end
        next unless content.includes?("urlpatterns")

        django_urls = DjangoUrls.new("", file, candidate_base_path)
        extract_endpoints(django_urls).each do |endpoint|
          endpoints << endpoint
        end
        @visited_url_paths.each_key { |key| visited << Noir::PathScope.expand(key) }
      end

      endpoints
    end

    # Django Channels: the lists handed to `URLRouter(...)` (normally the
    # `"websocket"` branch of a `ProtocolTypeRouter`) are WebSocket routes,
    # separate from `urlpatterns`. Roots are `URLRouter` calls that are not a
    # `path(prefix, URLRouter(...))` view; nested ones are expanded under
    # their prefix. A `websocket_urlpatterns` list no root reached (an app
    # scanned without its `asgi.py`) is reported app-relative.
    private def extract_channels_endpoints : Array(Endpoint)
      endpoints = [] of Endpoint
      sources = [] of Tuple(::String, ::String)
      python_source_files.each do |file|
        content = read_file_content(file) rescue next
        sources << {file, channels_code(content)} if content.includes?("URLRouter") || content.includes?("websocket_urlpatterns")
      end
      return endpoints if sources.empty?

      visited = Set(Tuple(::String, ::String)).new
      sources.each do |file, content|
        content.scan(/URLRouter\s*\(/) do |match|
          # A `path(prefix, URLRouter(...))` view, also behind a middleware
          # wrapper (`path(prefix, AuthMiddlewareStack(URLRouter(...)))`),
          # is expanded under its prefix by the router that holds it.
          before = content[0, match.begin(0)]
          next if before.rstrip.ends_with?(',') || before[(before.rindex('\n') || -1) + 1..].matches?(/\b(?:re_)?path\s*\(/)
          if arg = channels_router_arg(content, match.end(0) - 1)
            channels_list_endpoints(file, content, arg, "", visited, endpoints)
          end
        end
      end
      # An unmounted `websocket_urlpatterns` serves at the root; one already
      # mounted under any prefix is not repeated there, and a file that only
      # imports the name is not its home.
      sources.each do |file, content|
        next unless content.matches?(WS_PATTERNS_ASSIGN)
        next if visited.any? { |(seen, key)| seen == file && key.ends_with?("\0websocket_urlpatterns") }
        channels_list_endpoints(file, content, "websocket_urlpatterns", "", visited, endpoints)
      end
      endpoints
    end

    WS_PATTERNS_ASSIGN = /^\s*websocket_urlpatterns\s*(?::[^=\n]*)?\+?=/m

    # `content` with comments cut and docstring lines blanked (line count
    # kept), so a commented-out or documented `URLRouter(...)` is not a route.
    private def channels_code(content : ::String) : ::String
      lines = content.split('\n')
      docstring = Helper.docstring_line_flags(lines)
      lines.map_with_index { |line, idx| docstring[idx] ? "" : strip_python_comment(line) }.join('\n')
    end

    # The argument text of the `URLRouter(` whose `(` sits at char `open`.
    private def channels_router_arg(text : ::String, open : Int32) : ::String?
      byte_open = text.char_index_to_byte_index(open) || return
      close = python_close_paren_byte(text.to_slice, byte_open) || return
      text.byte_slice(byte_open + 1, close - byte_open - 1).strip
    end

    private def channels_list_endpoints(file : ::String, content : ::String, arg : ::String, prefix : ::String,
                                        visited : Set(Tuple(::String, ::String)), endpoints : Array(Endpoint),
                                        active = Set(Tuple(::String, ::String)).new) : Nil
      terms = split_python_expression_terms(arg)
      if terms.size > 1 # `a.websocket_urlpatterns + [...]`
        terms.each { |term| channels_list_endpoints(file, content, term.strip, prefix, visited, endpoints, active) }
        return
      end
      entered = nil

      list = arg
      unless arg.starts_with?('[')
        module_name, _, name = arg.rpartition('.')
        # Keyed by prefix too: one list mounted under two prefixes serves
        # both. `active` holds the lists being expanded, so a list that
        # mounts itself (directly or through another) stops there.
        return unless visited.add?({file, "#{prefix}\0#{arg}"})
        return unless active.add?({file, arg})
        entered = {file, arg}
        if module_name.empty?
          if local = extract_urlpattern_lists(content)[name]?
            list = local
          elsif target = channels_import_target(content, name)
            module_name, _, name = target.rpartition('.')
          else
            return
          end
        elsif target = channels_import_target(content, module_name.partition('.')[0])
          # `from chat import routing` + `routing.websocket_urlpatterns`.
          rest = module_name.partition('.')[2]
          module_name = rest.empty? ? target : "#{target}.#{rest}"
        end
        unless module_name.empty?
          target = channels_module_file(file, module_name) || return
          return channels_list_endpoints(target, channels_code(read_file_content(target)), name, prefix, visited, endpoints, active)
        end
      end

      list_start = content.index(list) || 0
      extract_route_mappings(list).each do |route, view, _offset|
        url = join_url_parts(prefix, normalize_django_route(route))
        line = route.empty? ? nil : content.index(route, list_start).try { |idx| content[0, idx].count('\n') + 1 }
        if router = view.index("URLRouter(")
          inner = channels_router_arg(view, router + "URLRouter".size)
          channels_list_endpoints(file, content, inner, url, visited, endpoints, active) if inner
        else
          endpoint = Endpoint.new(url, "GET", Details.new(PathInfo.new(file, line)))
          endpoint.protocol = "ws"
          endpoints << endpoint
        end
      end
    ensure
      active.delete(entered) if entered
    end

    # The dotted path `name` is bound to by this file's imports:
    # `from chat import routing` -> `chat.routing`, `import game.routing as
    # gr` -> `game.routing`, `from chat.routing import urls as ws` ->
    # `chat.routing.urls`.
    private def channels_import_target(content : ::String, name : ::String) : ::String?
      escaped = Regex.escape(name)
      if m = content.match(/^\s*from\s+([\w.]+)\s+import\s+[^\n]*?\b(\w+)\s+as\s+#{escaped}\b/m)
        module_name, imported = m[1], m[2]
      elsif m = content.match(/^\s*import\s+([\w.]+)\s+as\s+#{escaped}\b/m)
        return m[1]
      elsif m = content.match(/^\s*from\s+([\w.]+)\s+import\s+[^\n]*\b#{escaped}\b/m)
        module_name, imported = m[1], name
      else
        return
      end
      module_name.ends_with?('.') ? "#{module_name}#{imported}" : "#{module_name}.#{imported}"
    end

    # `chat.routing` -> `chat/routing.py` (or a package `__init__.py`); a
    # relative `.routing` resolves beside `file`.
    private def channels_module_file(file : ::String, module_name : ::String) : ::String?
      relative = module_name.lstrip('.').gsub('.', '/')
      if module_name.starts_with?('.')
        candidate = File.join(File.dirname(file), "#{relative}.py")
        return candidate if File.file?(candidate)
      end
      {"#{relative}.py", "#{relative}/__init__.py"}.each do |path|
        found = get_files_by_relative_path(path, python_base_path_for(file)).first?
        return found if found
      end
      nil
    end

    # Find all root Django URLs
    def find_root_django_urls : Array(DjangoUrls)
      root_django_urls_list = [] of DjangoUrls

      # Driven by the shared pool on `Analyzer`. See the note in
      # `java/armeria.cr`: the inlined pool this replaces closed the channel
      # outside an `ensure` and caught only `IO::Error`, so a non-IO failure
      # in a worker killed the worker and hung the whole scan once every
      # worker was gone.
      parallel_analyze(all_files) do |file|
        # No `File.directory?` — `all_files` is `file_map`, which
        # holds regular files only.
        next if base_relative_path(file).includes?("/site-packages/")
        # `django_settings_path?` is pure string work and rejects
        # all but a handful of files, so it runs before
        # `base_path_for` / `python_test_path?`. Every gate here
        # is a pure predicate and all of them must pass, so the
        # order is free to favour the cheapest, most selective
        # one — previously each of the tens of thousands of
        # non-settings files paid the base-path resolution first.
        next unless django_settings_path?(file)
        # Skip Python test files: each Django test app under
        # `tests/<feature>/` carries its own `ROOT_URLCONF`
        # the analyzer would otherwise treat as a real Django
        # project root. Django's own repo contributes ~720
        # such phantom endpoints. Standard test conventions
        # (`tests/` dir, `tests.py`, `test_*.py`, `*_test.py`)
        # are unambiguous in Python codebases.
        current_base_path = base_path_for(file)
        next if PythonEngine.python_test_path?(file, current_base_path)
        next unless file.ends_with? ".py"

        content = read_file_content(file)
        content.each_line do |line|
          next if line.lstrip.starts_with?("#")

          line.scan(REGEX_ROOT_URLCONF) do |match|
            next if match.size != 2
            dotted_as_urlconf = match[1].split(".")
            resolve_root_urlconf_paths(file, dotted_as_urlconf, current_base_path).each do |filepath|
              basepath = filepath.split("/")[..-(dotted_as_urlconf.size + 1)].join("/")
              root_django_urls_list << DjangoUrls.new("", filepath, basepath)
            end
          end
        end
      end

      root_django_urls_list.uniq
    end

    private def base_path_for(file : ::String) : ::String
      python_base_path_for(file)
    end

    private def django_settings_path?(path : ::String) : Bool
      base = File.basename(path)
      return true if base == "settings.py"
      return true if base.ends_with?("_settings.py")
      path.includes?("/settings/")
    end

    private def resolve_root_urlconf_paths(settings_file : ::String,
                                           dotted_as_urlconf : Array(::String),
                                           search_dir : ::String) : Array(::String)
      relative_path = "#{dotted_as_urlconf.join("/")}.py"

      if dotted_as_urlconf.size == 1
        candidates = [
          File.join(File.dirname(settings_file), relative_path),
          File.join(search_dir, relative_path),
        ]
        return candidates.select { |path| File.exists?(path) }.uniq!
      end

      # Resolve against the scanned file index rather than
      # `Dir.glob("#{search_dir}/**/#{relative_path}")`. The glob walks
      # every directory under the scan root on each call — and this runs
      # once per ROOT_URLCONF line per `settings.py`, so a monorepo with
      # many Django services paid a full filesystem traversal per
      # service. On a 44k-file corpus that single glob was ~73% of the
      # whole analysis phase; the index lookup is O(files named
      # `urls.py`) with no syscalls. See `get_files_by_relative_path`
      # for the (deliberate) scope difference on excluded subtrees.
      get_files_by_relative_path(relative_path, search_dir)
    end

    # Extract endpoints from a Django URL configuration file
    def extract_endpoints(django_urls : DjangoUrls) : Array(Endpoint)
      logger.debug "Extracting endpoints from #{django_urls.filepath}"
      endpoints = [] of Endpoint
      url_base_path = File.dirname(django_urls.filepath)
      @visited_url_paths[django_urls.filepath] = true

      # Prefer the detector-cached content over a fresh disk read; falls
      # back to File.read (same encoding: utf-8, invalid: :skip) when the
      # file wasn't cached. Byte-identical either way, so the char-offset
      # -> line-number math further down is unaffected.
      content = read_file_content(django_urls.filepath)
      original_content = content
      package_map = find_imported_modules(@django_base_path, url_base_path, content)
      import_aliases = extract_python_import_aliases(original_content)
      app_config_refs = extract_django_app_config_refs(original_content)
      drf_router_registrations = extract_drf_router_registrations(content)
      urlpattern_lists = extract_urlpattern_lists(content)
      route_path = PathInfo.new(django_urls.filepath)

      direct_router_endpoints = extract_drf_direct_router_endpoints(
        django_urls,
        original_content,
        drf_router_registrations,
        package_map,
        import_aliases,
        route_path
      )

      urlpatterns_contents = extract_urlpatterns_contents(original_content, urlpattern_lists)
      return direct_router_endpoints if urlpatterns_contents.empty?

      urlpatterns_contents.each do |urlpatterns_content|
        list_line = list_start_line(original_content, urlpatterns_content)
        splatted_router_names(urlpatterns_content).each do |router_name|
          endpoints.concat extract_drf_router_endpoints_for_router(django_urls, "", router_name, drf_router_registrations,
            package_map, import_aliases, route_path)
        end
        extract_route_mappings(urlpatterns_content).each do |route_mapping|
          route, view, offset = route_mapping
          entry_path = route_entry_path(route_path, list_line, offset)
          route = normalize_django_route(route)
          url = "/#{django_urls.prefix}/#{route}".gsub(/\/+/, "/")
          if new_route_path = resolve_dotted_include_target(view)
            new_django_urls = DjangoUrls.new("#{django_urls.prefix}#{route}", new_route_path, django_urls.basepath)
            unless @visited_url_paths.has_key? new_django_urls.filepath
              extract_endpoints(new_django_urls).each do |endpoint|
                append_code_path(endpoint.details, PathInfo.new(new_route_path))
                endpoints << endpoint
              end
            end
            next
          end

          if app_config_path = resolve_django_app_config_include_path(view, app_config_refs)
            extract_endpoints_from_django_app_config(join_url_parts(django_urls.prefix, route).lchop("/"), app_config_path, entry_path).each do |endpoint|
              endpoints << endpoint
            end
            next
          end

          if imported_urlconf_path = extract_imported_include_target(view, package_map, django_urls.filepath)
            new_django_urls = DjangoUrls.new("#{django_urls.prefix}#{route}", imported_urlconf_path, django_urls.basepath)
            unless @visited_url_paths.has_key? new_django_urls.filepath
              extract_endpoints(new_django_urls).each do |endpoint|
                append_code_path(endpoint.details, PathInfo.new(imported_urlconf_path))
                endpoints << endpoint
              end
            end
            next
          end

          if inline_patterns = extract_inline_include_patterns(view)
            extract_local_urlpattern_endpoints(django_urls, route, inline_patterns, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations).each do |endpoint|
              endpoints << endpoint
            end
            next
          end

          if local_patterns = extract_local_include_target(view)
            if pattern_content = urlpattern_lists[local_patterns]?
              extract_local_urlpattern_endpoints(django_urls, route, pattern_content, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations, [local_patterns]).each do |endpoint|
                endpoints << endpoint
              end
              next
            end
          end

          if router_name = extract_drf_router_include_target(view)
            router_endpoints = extract_drf_router_endpoints_for_router(
              django_urls,
              route,
              router_name,
              drf_router_registrations,
              package_map,
              import_aliases,
              route_path
            )
            unless router_endpoints.empty?
              endpoints.concat(router_endpoints)
              next
            end
          end

          if view.empty?
            endpoints << Endpoint.new(url, "GET", Details.new(entry_path))
          else
            wrapper = urlconf_auth_wrapper(view)
            view = extract_wrapped_view_reference(view)
            if view_target = resolve_django_view_target(view, package_map)
              filepath, function_or_class_name = view_target
              extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
                append_code_path(endpoint.details, entry_path)
                endpoints << tag_urlconf_auth(endpoint, wrapper)
              end
            else
              # By default, Django allows requests with methods other than GET as well
              unresolved_view_endpoints(url, view, original_content, entry_path).each do |endpoint|
                endpoints << tag_urlconf_auth(endpoint, wrapper)
              end
            end
          end
        end
      end

      endpoints.concat(direct_router_endpoints)
      endpoints
    end

    # 1-based line in `content` where the list body `body` starts, or nil
    # when `body` is not a verbatim slice of it (a rewritten binding).
    private def list_start_line(content : ::String, body : ::String) : Int32?
      start = content.index(body) || return
      content[0, start].count('\n') + 1
    end

    # `route_path` pointed at the entry `offset` lines into the list that
    # starts at `list_line`; the bare file path when that line is unknown.
    private def route_entry_path(route_path : PathInfo, list_line : Int32?, offset : Int32) : PathInfo
      list_line ? PathInfo.new(route_path.path, list_line + offset) : route_path
    end

    private def extract_urlpatterns_contents(content : ::String, urlpattern_lists : Hash(::String, ::String)) : Array(::String)
      extract_url_list_contents(content, urlpattern_lists, ["urlpatterns"])
    end

    private def extract_app_config_url_contents(content : ::String, urlpattern_lists : Hash(::String, ::String)) : Array(::String)
      extract_url_list_contents(content, urlpattern_lists, ["urls", "urlpatterns"])
    end

    private def extract_url_list_contents(content : ::String,
                                          urlpattern_lists : Hash(::String, ::String),
                                          list_names : Array(::String)) : Array(::String)
      contents = [] of ::String
      lines = content.split("\n")
      # Compile once per call; interpolated regex literals inside the
      # per-line loop would be recompiled on every line.
      list_name_re = list_names.map { |name| Regex.escape(name) }.join("|")
      assign_check_re = /^\s*(?:#{list_name_re})\s*=/
      assign_capture_re = /^\s*(#{list_name_re})\s*=\s*(.+)$/m
      bindings = Hash(::String, ::String).new
      append_check_re = /^\s*(?:#{list_name_re})\s*\+=/
      append_capture_re = /^\s*(?:#{list_name_re})\s*\+=\s*(.+)$/m
      extend_check_re = /^\s*(?:#{list_name_re})\s*\.\s*extend\s*\(/
      extend_capture_re = /^\s*(?:#{list_name_re})\s*\.\s*extend\s*\((.*)\)\s*$/m

      lines.each_with_index do |line, index|
        if line.matches?(assign_check_re)
          logical_line = collect_python_expression(lines, index, line)
          if assignment_match = logical_line.match(assign_capture_re)
            name = assignment_match[1]
            expression = inline_previous_binding(assignment_match[2], name, bindings[name]?)
            bindings[name] = expression if expression.lstrip.starts_with?('[')
            add_urlpattern_expression_contents(contents, expression, urlpattern_lists)
          end
        elsif line.matches?(append_check_re)
          logical_line = collect_python_expression(lines, index, line)
          if append_match = logical_line.match(append_capture_re)
            add_urlpattern_expression_contents(contents, append_match[1], urlpattern_lists)
          end
        elsif line.matches?(extend_check_re)
          logical_line = collect_python_expression(lines, index, line)
          if extend_match = logical_line.match(extend_capture_re)
            add_urlpattern_expression_contents(contents, extend_match[1], urlpattern_lists)
          end
        end
      end

      contents.uniq
    end

    private def collect_python_expression(lines : Array(::String), index : Int32, line : ::String) : ::String
      pieces = [line]
      delta = python_paren_delta(line) + python_bracket_delta(line)
      line_index = index + 1
      while line_index < lines.size && delta > 0
        pieces << lines[line_index]
        delta += python_paren_delta(lines[line_index]) + python_bracket_delta(lines[line_index])
        line_index += 1
      end

      pieces.join("\n")
    end

    private def add_urlpattern_expression_contents(contents : Array(::String),
                                                   expression : ::String,
                                                   urlpattern_lists : Hash(::String, ::String)) : Nil
      split_python_expression_terms(expression).each do |term|
        term = term.strip
        next if term.empty? || term == "urlpatterns"

        if term.matches?(/\b(?:url|path|re_path)\s*\(/)
          contents << term
          next
        end

        identifier_match = term.match(/\A([A-Za-z_][A-Za-z0-9_]*)\z/)
        next unless identifier_match

        if pattern_content = urlpattern_lists[identifier_match[1]]?
          contents << pattern_content
        end
      end
    end

    # Same rules as `split_python_arguments`, splitting on `+` instead of `,`
    # so a concatenated URL-prefix expression breaks into its terms.
    private def split_python_expression_terms(expression : ::String) : Array(::String)
      Noir::TopLevelSplit.split(expression, '+', Noir::TopLevelSplit::Rules::PYTHON)
    end

    # `x = [path(.., include(x))]` includes the *previous* binding of x, not
    # itself: inline it so the include resolves instead of recursing forever.
    private def inline_previous_binding(text : ::String, name : ::String, previous : ::String?) : ::String
      # ponytail: size cap, since a rebind that includes itself twice doubles
      # per binding (2^n); past the cap the `seen` guard just cuts the cycle.
      return text if previous.nil? || previous.bytesize > 65_536
      text.gsub(/\binclude\s*\(\s*#{Regex.escape(name)}\s*\)/) { "include(#{previous})" }
    end

    private def extract_urlpattern_lists(content : ::String) : Hash(::String, ::String)
      pattern_lists = Hash(::String, ::String).new
      lines = content.split("\n")

      lines.each_with_index do |line, index|
        assignment_match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\[/)
        next unless assignment_match

        pieces = [line]
        delta = python_bracket_delta(line)
        line_index = index + 1
        while line_index < lines.size && delta > 0
          pieces << lines[line_index]
          delta += python_bracket_delta(lines[line_index])
          line_index += 1
        end

        name = assignment_match[1]
        pattern_lists[name] = inline_previous_binding(pieces.join("\n"), name, pattern_lists[name]?)
      end

      pattern_lists
    end

    # Attribute name → right-hand side of each `self.X = ...` an AppConfig
    # binds in `ready()`: another app config (`apps.get_app_config("x")`)
    # or a view class (`get_class("basket.views", "BasketView")`,
    # `views.BasketView`) that `get_urls` then mounts as `self.X.as_view()`.
    private def extract_django_app_config_refs(content : ::String) : Hash(::String, ::String)
      refs = Hash(::String, ::String).new
      lines = content.split("\n")
      lines.each_with_index do |line, index|
        next unless line.includes?("self.")
        assignment = line.match(/^\s*self\.([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)\s*(.+)$/) || next
        expression = python_paren_delta(line) > 0 ? collect_python_expression(lines, index, line).partition(/=\s*/)[2] : assignment[2]
        refs[assignment[1]] = expression.strip
      end
      refs
    end

    APP_CONFIG_LABEL_RE = /\bapps\.get_app_config\s*\(\s*['"]([^'"]+)['"]\s*\)/

    private def resolve_django_app_config_include_path(view : ::String,
                                                       app_config_refs : Hash(::String, ::String)) : ::String?
      if direct_match = view.match(/\bapps\.get_app_config\s*\(\s*['"]([^'"]+)['"]\s*\)\.urls\b/)
        return resolve_django_app_config_path(direct_match[1])
      end

      if self_match = view.match(/\bself\.([A-Za-z_][A-Za-z0-9_]*)\.urls\b/)
        ref_name = self_match[1]
        if label = app_config_refs[ref_name]?.try(&.match(APP_CONFIG_LABEL_RE)).try(&.[1])
          resolve_django_app_config_path(label)
        end
      end
    end

    # `self.add_view` in an AppConfig's `get_urls` → `{views file, class}`
    # through the `ready()` binding. Oscar's `get_class("basket.views",
    # "BasketAddView")` names a module by its app-relative dotted path, so
    # it resolves to the `basket/views.py` nearest the apps.py; any other
    # expression (`views.BasketAddView`) goes through the file's imports.
    # ponytail: an Oscar fork overriding the module elsewhere in the
    # tree is not preferred over the original.
    private def resolve_app_config_view_target(view : ::String, app_config_refs : Hash(::String, ::String),
                                               app_config_path : ::String, package_map) : Tuple(::String, ::String)?
      expression = app_config_refs[view.lchop?("self.") || return]? || return
      if loader = expression.match(/\bget_class\s*\(\s*['"]([\w.]+)['"]\s*,\s*['"](\w+)['"]/)
        file = get_class_module_file(loader[1], app_config_path)
        return file ? {file, loader[2]} : nil
      end
      resolve_django_view_target(expression, package_map)
    end

    # The file an Oscar loader's app-relative dotted module (`basket.views`)
    # names: `basket/views.py` or `basket/views/__init__.py`, preferring the
    # one under `near`'s directory.
    private def get_class_module_file(dotted : ::String, near : ::String) : ::String?
      near_dir = "#{File.dirname(near)}/"
      relative = dotted.gsub('.', '/')
      # Whole tree, not `@django_base_path`: the loader walks INSTALLED_APPS,
      # and the sandbox project that anchors the scan does not contain them.
      candidates = get_files_by_relative_path("#{relative}.py") + get_files_by_relative_path("#{relative}/__init__.py")
      candidates.find(&.starts_with?(near_dir)) || candidates.min_by? { |c| {c.count('/'), c} }
    end

    # Where `name` really lives when `filepath` only re-binds it at module
    # level: `X = get_class("search.views", "X")`, a `get_classes(...)`
    # tuple, or `from .catalogue import Y as X`. Nil when it is bound some
    # other way, or not at all.
    private def resolve_view_reexport(filepath : ::String, content : ::String, name : ::String) : Tuple(::String, ::String)?
      content.scan(VIEW_LOADER_BINDING_RE) do |binding|
        index = binding[1].delete("()").split(',').map(&.strip).index(name) || next
        target = binding[3].scan(/['"](\w+)['"]/)[index]?.try(&.[1]) || next
        file = get_class_module_file(binding[2], filepath) || next
        return {file, target}
      end
      file, original = Noir::ImportGraph::Python.find_imported_symbols(@django_base_path, filepath, content)[name]? || return
      {file, original} unless original.empty?
    end

    # A urlconf view nothing in the tree defines. Django's own class-based
    # views (`auth_views.PasswordResetView`, `generic.RedirectView`) get
    # the verbs they accept and the reference as a location-less handler;
    # anything else stays a bare GET.
    # ponytail: the import is read one line at a time, so a parenthesised
    # multi-line `from django... import (...)` does not count.
    private def unresolved_view_endpoints(url : ::String, view : ::String, content : ::String,
                                          entry_path : PathInfo) : Array(Endpoint)
      root = view.partition('.')[0]
      methods = DJANGO_BUILTIN_VIEW_METHODS[view.rpartition('.')[2]]?
      django_import = methods && content.each_line.any? do |line|
        statement = line.strip
        statement.starts_with?("from django") &&
          statement.partition(" import ")[2].split(',').any? { |spec| spec.split(/\s+as\s+/).last.strip == root }
      end
      return [Endpoint.new(url, "GET", Details.new(entry_path))] unless methods && django_import

      methods.map do |method|
        endpoint = Endpoint.new(url, method, Details.new(entry_path))
        endpoint.handler = Handler.new(view)
        endpoint
      end
    end

    private def resolve_django_app_config_path(label : ::String) : ::String?
      cache_key = "#{@django_base_path}:#{label}"
      if cached = @django_app_config_path_cache[cache_key]?
        return cached.empty? ? nil : cached
      end

      escaped_label = Regex.escape(label)
      label_re = Regex.new("^\\s*label\\s*=\\s*[r]?['\"]#{escaped_label}['\"]")
      exact_name_re = Regex.new("^\\s*name\\s*=\\s*[r]?['\"]#{escaped_label}['\"]")
      tail_name_re = Regex.new("^\\s*name\\s*=\\s*[r]?['\"][^'\"]*\\.#{escaped_label}['\"]")

      candidates = all_files.select do |file|
        next false unless file.ends_with?(".py")
        next false if base_relative_path(file).includes?("/site-packages/")
        next false if PythonEngine.python_test_path?(file, base_path_for(file))
        base = File.basename(file)
        base == "apps.py" || base == "config.py"
      end
      candidates.sort_by! { |file| {file.ends_with?("/config.py") ? 0 : 1, file.count('/'), file} }

      candidates.each do |file|
        begin
          content = read_file_content(file)
        rescue
          next
        end

        if content.each_line.any? { |line| line.matches?(label_re) || line.matches?(exact_name_re) || line.matches?(tail_name_re) }
          @django_app_config_path_cache[cache_key] = file
          return file
        end
      end

      @django_app_config_path_cache[cache_key] = ""
      nil
    end

    private def extract_endpoints_from_django_app_config(prefix : ::String,
                                                         app_config_path : ::String,
                                                         parent_route_path : PathInfo) : Array(Endpoint)
      endpoints = [] of Endpoint
      expanded_key = "#{Noir::PathScope.expand(app_config_path)}:#{prefix}"
      return endpoints if @visited_app_config_paths.includes?(expanded_key)
      @visited_app_config_paths << expanded_key

      begin
        content = read_file_content(app_config_path)
        package_map = find_imported_modules(@django_base_path, File.dirname(app_config_path), content)
        urlpattern_lists = extract_urlpattern_lists(content)
        app_config_refs = extract_django_app_config_refs(content)
        route_path = PathInfo.new(app_config_path)

        extract_app_config_url_contents(content, urlpattern_lists).each do |pattern_content|
          extract_app_config_pattern_endpoints(prefix, pattern_content, app_config_path, package_map, urlpattern_lists, app_config_refs, route_path, parent_route_path).each do |endpoint|
            endpoints << endpoint
          end
        end
      rescue e
        logger.debug e.message
      end

      endpoints
    end

    private def extract_app_config_pattern_endpoints(prefix : ::String,
                                                     pattern_content : ::String,
                                                     current_app_config_path : ::String,
                                                     package_map,
                                                     urlpattern_lists : Hash(::String, ::String),
                                                     app_config_refs : Hash(::String, ::String),
                                                     route_path : PathInfo,
                                                     parent_route_path : PathInfo,
                                                     seen : Array(::String) = [] of ::String) : Array(Endpoint)
      endpoints = [] of Endpoint

      list_line = list_start_line(read_file_content(current_app_config_path), pattern_content)
      extract_route_mappings(pattern_content).each do |route_mapping|
        route, view, offset = route_mapping
        entry_path = route_entry_path(route_path, list_line, offset)
        route = normalize_django_route(route)
        nested_prefix = join_url_parts(prefix, route).lchop("/")

        if nested_app_config_path = resolve_django_app_config_include_path(view, app_config_refs)
          extract_endpoints_from_django_app_config(nested_prefix, nested_app_config_path, entry_path).each do |endpoint|
            append_code_path(endpoint.details, parent_route_path)
            endpoints << endpoint
          end
          next
        end

        if local_patterns = extract_local_include_target(view)
          if !seen.includes?(local_patterns) && (nested_pattern_content = urlpattern_lists[local_patterns]?)
            extract_app_config_pattern_endpoints(nested_prefix, nested_pattern_content, current_app_config_path, package_map, urlpattern_lists, app_config_refs, route_path, parent_route_path, seen + [local_patterns]).each do |endpoint|
              endpoints << endpoint
            end
            next
          end
        end

        if inline_patterns = extract_inline_include_patterns(view)
          extract_app_config_pattern_endpoints(nested_prefix, inline_patterns, current_app_config_path, package_map, urlpattern_lists, app_config_refs, route_path, parent_route_path, seen).each do |endpoint|
            endpoints << endpoint
          end
          next
        end

        if imported_urlconf_path = extract_imported_include_target(view, package_map, current_app_config_path)
          new_django_urls = DjangoUrls.new(nested_prefix, imported_urlconf_path, @django_base_path)
          unless @visited_url_paths.has_key? new_django_urls.filepath
            extract_endpoints(new_django_urls).each do |endpoint|
              append_code_path(endpoint.details, entry_path)
              append_code_path(endpoint.details, parent_route_path)
              endpoints << endpoint
            end
          end
          next
        end

        url = join_url_parts(prefix, route)
        if view.empty?
          endpoint = Endpoint.new(url, "GET", Details.new(entry_path))
          append_code_path(endpoint.details, parent_route_path)
          endpoints << endpoint
        else
          wrapper = urlconf_auth_wrapper(view)
          view = extract_wrapped_view_reference(view)
          view_target = resolve_django_view_target(view, package_map) ||
                        resolve_app_config_view_target(view, app_config_refs, current_app_config_path, package_map)
          if view_target
            filepath, function_or_class_name = view_target
            extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
              append_code_path(endpoint.details, entry_path)
              append_code_path(endpoint.details, parent_route_path)
              endpoints << tag_urlconf_auth(endpoint, wrapper)
            end
          else
            unresolved_view_endpoints(url, view, read_file_content(current_app_config_path), entry_path).each do |endpoint|
              append_code_path(endpoint.details, parent_route_path)
              endpoints << tag_urlconf_auth(endpoint, wrapper)
            end
          end
        end
      end

      endpoints
    end

    private def resolve_django_view_target(view : ::String, package_map) : Tuple(::String, ::String)?
      dotted_as_names_split = view.split(".")

      dotted_as_names_split.each_with_index do |name, index|
        if (package_map.has_key? name) && (index < dotted_as_names_split.size)
          filepath, package_type = package_map[name]
          function_or_class_name = name
          if package_type == PackageType::FILE && index + 1 < dotted_as_names_split.size
            function_or_class_name = dotted_as_names_split[index + 1]
          end

          return {filepath, function_or_class_name} if !filepath.empty? && /^[a-zA-Z_][a-zA-Z0-9_]*$/.match(function_or_class_name)
        end
      end

      nil
    end

    # Argument lists of each top-level `url|path|re_path|register(...)` call
    # in `text`. A call nested in another's arguments (an inline
    # `include([...])` body) is skipped here and read when that include is
    # expanded. Scans bytes: every delimiter is ASCII, so UTF-8 is safe and
    # each call costs one forward pass.
    private def route_call_args(text : ::String) : Array(Array(::String))
      calls = [] of Array(::String)
      bytes = text.to_slice
      pos = 0
      while call = /\b(?:url|path|re_path|register)\s*\(/.match_at_byte_index(text, pos)
        open = call.byte_end(0) - 1
        close = python_close_paren_byte(bytes, open)
        break unless close
        calls << split_python_arguments(text.byte_slice(open + 1, close - open - 1))
        pos = close + 1
      end
      calls
    end

    # Byte index of the `)` closing the `(` at `open`, skipping quoted runs.
    private def python_close_paren_byte(bytes : Bytes, open : Int32) : Int32?
      depth = 0
      quote : UInt8? = nil
      escaped = false
      (open...bytes.size).each do |i|
        b = bytes[i]
        if quote
          if escaped
            escaped = false
          elsif b === '\\'
            escaped = true
          elsif b == quote
            quote = nil
          end
        elsif b === '\'' || b === '"'
          quote = b
        elsif b === '('
          depth += 1
        elsif b === ')'
          depth -= 1
          return i if depth == 0
        end
      end
      nil
    end

    # `{route, view, line offset}` per `path|re_path|url(...)` entry in
    # `content`; the offset is the entry's 0-based line within `content`,
    # for `route_entry_path` to turn into a file line.
    private def extract_route_mappings(content : ::String) : Array(Tuple(::String, ::String, Int32))
      mappings = [] of Tuple(::String, ::String, Int32)
      # Comments go first: a commented-out `path(...)` or a `(` in a
      # trailing comment would otherwise be read as code once lines are
      # joined into one logical call.
      lines = content.split("\n").map { |line| strip_python_comment(line) }
      # Last line of the call just read: every top-level call on it is
      # already mapped, and a call nested in its arguments (an inline
      # `include([...])` or Channels `URLRouter([...])` body, however its
      # brackets wrap) is read when that include is expanded.
      skip_through = -1
      # `i18n_patterns(path(...), ...)` serves everything it holds under a
      # language-code segment (`/en/basket/`); `{lang}` stands for it.
      # ponytail: `prefix_default_language=False` also serves the bare path
      # for the default language; that twin is not emitted.
      i18n = content.lstrip.starts_with?("i18n_patterns")

      lines.each_with_index do |line, index|
        next if index <= skip_through
        next if line.lstrip.starts_with?("#")
        next unless line.matches?(/\b(?:url|path|re_path|register)\s*\(/)

        logical_line, call_end = python_paren_delta(line) > 0 ? python_call_span(lines, index, line) : {line, index}
        mapped_before = mappings.size

        # One line can hold several sibling calls (`[path('a', v), path('b', w)]`,
        # or an inline `include([...])` body), so read every top-level call.
        route_call_args(logical_line).each do |args|
          next if args.size < 2

          view_expr = extract_python_keyword_expression(args, "view")
          view_expr ||= args[1]?.try do |candidate|
            if keyword_view = candidate.match(/^\s*view\s*=\s*(.+)$/m)
              keyword_view[1].strip
            else
              candidate.strip
            end
          end
          view_expr ||= ""

          route = Helper.extract_python_string(args[0])
          route ||= extract_python_keyword_string(args, "route")
          route ||= extract_python_keyword_string(args, "regex")

          # A route prefix that isn't a string literal — the canonical shape is
          # a deployment sub-path pulled from settings, e.g. NetBox's root
          # urlconf, which is nothing but
          # `urlpatterns = [path(settings.BASE_PATH, include(_patterns))]`.
          # Skipping the whole entry threw away not just the prefix but every
          # route the `include()` mounts: NetBox's entire URL tree hung off
          # that one line, so the ROOT_URLCONF pass returned zero and the
          # orphan-urlconf fallback re-derived each app's routes app-relative,
          # dropping the `/api/<app>/` mount that distinguishes the REST API
          # from the web UI.
          #
          # Mounting the subtree at the empty prefix is the right recovery:
          # these settings-driven prefixes are empty in the default deployment
          # (BASE_PATH is `''` unless the operator serves NetBox under a
          # sub-path), so the paths are exactly right far more often than not,
          # and a missing leading segment is a much smaller error than a
          # missing API. The tolerance is deliberately limited to `include()`
          # views: for a leaf `path(some_var, view)` there is no subtree to
          # rescue, and guessing `/` for it would invent an endpoint.
          route ||= "" if view_expr.matches?(/\binclude\s*\(/)
          next unless route

          route = "{lang}/#{Noir::URLPath.strip_regex_anchors(route)}" if i18n
          mappings << {route, view_expr, index}
        end

        skip_through = call_end if mappings.size > mapped_before
      end

      mappings
    end

    private def normalize_django_route(route : ::String) : ::String
      normalized = Noir::URLPath.strip_regex_anchors(route)
      normalized = normalize_django_named_regex_groups(normalized)
      # `logo(?:/{filename})?` — an optional non-capturing segment is one of
      # the paths the pattern matches; keep its text like `/?` keeps `/`.
      normalized = normalized.gsub(/\(\?:([^()|]*)\)\??/, "\\1") if normalized.includes?("(?:")
      strip_django_optional_quantifiers(normalized)
    end

    # `re_path(r'^tags/?$')` is the Django idiom for "trailing slash
    # optional", and `?` there is a regex quantifier on the preceding `/`,
    # not a character of the path. Carried through, it lands in the URL as
    # the query delimiter: `/tags/?` rendered with query params came out as
    # `/tags/??q=&page=`, so the first parameter reached the server named
    # `?q`. The anchors, the named groups and the `\.` escapes of a
    # `re_path` pattern are already translated out; this finishes the job
    # for the one quantifier that changes what the URL means.
    #
    # Only quantifiers whose target is a path token this method can keep
    # are dropped: `/?` keeps the slash (one of the two paths the pattern
    # matches), and `{name}?` keeps the parameter, since noir's URL shape
    # has no way to spell an optional segment. A `?` anywhere else belongs
    # to regex syntax the normalizer does not claim to translate (`(?:`,
    # `(?P<`, a lazy `+?`) and is left alone.
    private def strip_django_optional_quantifiers(route : ::String) : ::String
      return route unless route.includes?('?')

      String.build do |io|
        index = 0
        while index < route.size
          ch = route[index]
          if ch == '?' && index > 0 && optional_quantifier_target?(route[index - 1])
            index += 1
            next
          end
          io << ch
          index += 1
        end
      end
    end

    private def optional_quantifier_target?(previous : Char) : Bool
      previous == '/' || previous == '}'
    end

    private def normalize_django_named_regex_groups(route : ::String) : ::String
      normalized = String.build do |io|
        index = 0
        while index < route.size
          if route.byte_slice(index, 4) == "(?P<"
            name_start = index + 4
            name_end = route.index('>', name_start)
            unless name_end
              io << route[index]
              index += 1
              next
            end

            name = route[name_start...name_end]
            if name.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)
              group_end = django_named_group_end(route, name_end + 1)
              if group_end
                io << "{#{name}}"
                index = group_end + 1
                next
              end
            end
          end

          io << route[index]
          index += 1
        end
      end
      normalized
    end

    private def django_named_group_end(route : ::String, start_index : Int32) : Int32?
      depth = 1
      index = start_index
      in_char_class = false
      escaped = false

      while index < route.size
        ch = route[index]
        if escaped
          escaped = false
        elsif ch == '\\'
          escaped = true
        elsif in_char_class
          in_char_class = false if ch == ']'
        elsif ch == '['
          in_char_class = true
        elsif ch == '('
          depth += 1
        elsif ch == ')'
          depth -= 1
          return index if depth == 0
        end
        index += 1
      end

      nil
    end

    private def extract_python_import_aliases(content : ::String) : Hash(::String, ::String)
      aliases = Hash(::String, ::String).new
      lines = content.split("\n")

      lines.each_with_index do |line, index|
        next unless line.lstrip.starts_with?("from ")

        import_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        import_match = import_line.match(/from\s+[^'"\s\\]+\s+import\s+(.+)/m)
        next unless import_match

        imports = import_match[1].strip
        imports = imports.lchop("(").rchop(")").strip
        split_python_arguments(imports).each do |import_expr|
          import_expr = import_expr.gsub(/[()]/, "").strip
          next if import_expr.empty? || import_expr == "*"

          if alias_match = import_expr.match(/\A([A-Za-z_][A-Za-z0-9_]*)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)\z/)
            aliases[alias_match[2]] = alias_match[1]
          elsif name_match = import_expr.match(/\A([A-Za-z_][A-Za-z0-9_]*)\z/)
            aliases[name_match[1]] = name_match[1]
          end
        end
      end

      aliases
    end

    private def extract_drf_router_registrations(content : ::String) : Hash(::String, Array(DjangoDrfRegistration))
      registrations = Hash(::String, Array(DjangoDrfRegistration)).new do |hash, key|
        hash[key] = [] of DjangoDrfRegistration
      end
      # `DefaultRouter(trailing_slash=False)` drops the `/` DRF appends to
      # every route it builds.
      slashless = Set(::String).new
      content.scan(DRF_SLASHLESS_ROUTER_RE) { |match| slashless << match[1] }
      lines = content.split("\n")

      lines.each_with_index do |line, index|
        next if line.lstrip.starts_with?("#")
        next unless line.includes?(".register(")

        logical_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        register_match = logical_line.match(/\b([A-Za-z_][A-Za-z0-9_]*)\.register\s*\((.*)\)/m)
        next unless register_match

        args = split_python_arguments(register_match[2])
        next if args.empty?

        prefix = Helper.extract_python_string(args[0]) || extract_python_keyword_string(args, "prefix")
        next unless prefix

        view_ref = extract_python_keyword_expression(args, "viewset") || args[1]?.try(&.strip)
        next unless view_ref
        view_ref = clean_python_reference(view_ref)
        next if view_ref.empty?

        registrations[register_match[1]] << DjangoDrfRegistration.new(prefix, view_ref, !slashless.includes?(register_match[1]))
      end

      registrations
    end

    private def extract_drf_router_include_target(view : ::String) : ::String?
      include_match = view.match(/\binclude\s*\(\s*(?:\(\s*)?([A-Za-z_][A-Za-z0-9_]*)\.urls\b/)
      include_match ? include_match[1] : nil
    end

    private def extract_local_include_target(view : ::String) : ::String?
      include_match = view.match(/\binclude\s*\(\s*(?:\(\s*)?([A-Za-z_][A-Za-z0-9_]*)\b/)
      return unless include_match
      return if view.includes?("#{include_match[1]}.urls")

      include_match[1]
    end

    private def extract_inline_include_patterns(view : ::String) : ::String?
      # `include([...])`, or the `include(([...], "app_name"))` tuple form.
      include_match = view.match(/\binclude\s*\(\s*(?:\(\s*)?(\[[\s\S]*\])\s*(?:,\s*namespace\s*=|\))?/m)
      include_match ? include_match[1] : nil
    end

    # Resolve `include("app.sub.urls")` — the dotted-module form — against
    # the project root, returning the urlconf file it names: a module
    # (`app/sub/urls.py`) or a package (`app/sub/urls/__init__.py`).
    private def resolve_dotted_include_target(view : ::String) : ::String?
      view.scan(REGEX_INCLUDE_URLS) do |match|
        next if match.size != 2
        module_path = "#{@django_base_path}/#{match[1].gsub(".", "/")}"
        {"#{module_path}.py", "#{module_path}/__init__.py"}.each do |candidate|
          return candidate if File.file?(candidate)
        end
      end

      nil
    end

    private def extract_imported_include_target(view : ::String, package_map, urlconf_path : ::String) : ::String?
      include_match = view.match(/\binclude\s*\(\s*(?:\(\s*)?([A-Za-z_][A-Za-z0-9_]*)\b/)
      return unless include_match

      target_name = include_match[1]
      return imported_module_urls(target_name, urlconf_path) if view.includes?("#{target_name}.urls")
      imported = package_map[target_name]?
      return unless imported

      filepath, package_type = imported
      return unless package_type == PackageType::FILE
      return unless File.exists?(filepath)

      filepath
    end

    # `include(shop.urls)` after `import shop.urls` (or `import shop`): the
    # `shop/urls.py` urlconf. `X.urls` is otherwise a DRF router's url list,
    # which is never an imported module, so this resolves nothing for it.
    private def imported_module_urls(name : ::String, urlconf_path : ::String) : ::String?
      symbols = Noir::ImportGraph::Python.find_imported_symbols(@django_base_path, urlconf_path, read_file_content(urlconf_path))
      if (target = symbols["#{name}.urls"]?) && target[1].empty?
        return target[0]
      end
      module_file, attr = symbols[name]? || return
      return unless attr.empty? && File.basename(module_file) == "__init__.py"
      dir = File.dirname(module_file)
      {File.join(dir, "urls.py"), File.join(dir, "urls", "__init__.py")}.find { |candidate| File.file?(candidate) }
    end

    private def extract_local_urlpattern_endpoints(django_urls : DjangoUrls,
                                                   mount_route : ::String,
                                                   pattern_content : ::String,
                                                   package_map,
                                                   route_path : PathInfo,
                                                   urlpattern_lists : Hash(::String, ::String),
                                                   import_aliases : Hash(::String, ::String),
                                                   drf_router_registrations : Hash(::String, Array(DjangoDrfRegistration)),
                                                   seen : Array(::String) = [] of ::String) : Array(Endpoint)
      endpoints = [] of Endpoint

      list_line = list_start_line(read_file_content(django_urls.filepath), pattern_content)
      splatted_router_names(pattern_content).each do |router_name|
        endpoints.concat extract_drf_router_endpoints_for_router(django_urls, mount_route, router_name, drf_router_registrations,
          package_map, import_aliases, route_path)
      end
      extract_route_mappings(pattern_content).each do |route_mapping|
        route, view, offset = route_mapping
        entry_path = route_entry_path(route_path, list_line, offset)
        route = normalize_django_route(route)
        nested_mount = join_url_parts(mount_route, route).lchop("/")

        # `include("app.urls")` — the dotted-module form. `extract_endpoints`
        # has always followed it, but this sibling loop (a urlpatterns list
        # held in a local variable rather than assigned to `urlpatterns`) did
        # not, so a project that assembles its routes in a `_patterns` list
        # lost every app it mounts that way: the dotted include fell through
        # to view resolution and emitted a bare GET on the mount point
        # instead of the app's routes.
        if dotted_urlconf_path = resolve_dotted_include_target(view)
          new_django_urls = DjangoUrls.new(join_url_parts(django_urls.prefix, nested_mount).lchop("/"), dotted_urlconf_path, django_urls.basepath)
          unless @visited_url_paths.has_key? new_django_urls.filepath
            extract_endpoints(new_django_urls).each do |endpoint|
              append_code_path(endpoint.details, PathInfo.new(dotted_urlconf_path))
              endpoints << endpoint
            end
          end
          next
        end

        if local_patterns = extract_local_include_target(view)
          if !seen.includes?(local_patterns) && (nested_pattern_content = urlpattern_lists[local_patterns]?)
            extract_local_urlpattern_endpoints(django_urls, nested_mount, nested_pattern_content, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations, seen + [local_patterns]).each do |endpoint|
              endpoints << endpoint
            end
            next
          end
        end

        if inline_patterns = extract_inline_include_patterns(view)
          extract_local_urlpattern_endpoints(django_urls, nested_mount, inline_patterns, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations, seen).each do |endpoint|
            endpoints << endpoint
          end
          next
        end

        if imported_urlconf_path = extract_imported_include_target(view, package_map, django_urls.filepath)
          new_django_urls = DjangoUrls.new(join_url_parts(django_urls.prefix, nested_mount).lchop("/"), imported_urlconf_path, django_urls.basepath)
          unless @visited_url_paths.has_key? new_django_urls.filepath
            extract_endpoints(new_django_urls).each do |endpoint|
              append_code_path(endpoint.details, PathInfo.new(imported_urlconf_path))
              endpoints << endpoint
            end
          end
          next
        end

        if router_name = extract_drf_router_include_target(view)
          router_endpoints = extract_drf_router_endpoints_for_router(
            django_urls,
            nested_mount,
            router_name,
            drf_router_registrations,
            package_map,
            import_aliases,
            route_path
          )
          unless router_endpoints.empty?
            endpoints.concat(router_endpoints)
            next
          end
        end

        url = join_url_parts(django_urls.prefix, mount_route, route)
        if view.empty?
          endpoints << Endpoint.new(url, "GET", Details.new(entry_path))
          next
        end

        wrapper = urlconf_auth_wrapper(view)
        view = extract_wrapped_view_reference(view)
        resolved = resolve_django_view_reference(view, package_map)
        if resolved
          filepath, function_or_class_name = resolved
          if /^[a-zA-Z_][a-zA-Z0-9_]*$/.match(function_or_class_name)
            extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
              append_code_path(endpoint.details, entry_path)
              endpoints << tag_urlconf_auth(endpoint, wrapper)
            end
            next
          end
        end

        unresolved_view_endpoints(url, view, read_file_content(django_urls.filepath), entry_path).each do |endpoint|
          endpoints << tag_urlconf_auth(endpoint, wrapper)
        end
      end

      endpoints
    end

    private def extract_drf_direct_router_endpoints(django_urls : DjangoUrls,
                                                    content : ::String,
                                                    drf_router_registrations : Hash(::String, Array(DjangoDrfRegistration)),
                                                    package_map,
                                                    import_aliases : Hash(::String, ::String),
                                                    route_path : PathInfo) : Array(Endpoint)
      endpoints = [] of Endpoint

      extract_drf_direct_router_names(content).each do |router_name|
        endpoints.concat extract_drf_router_endpoints_for_router(
          django_urls,
          "",
          router_name,
          drf_router_registrations,
          package_map,
          import_aliases,
          route_path
        )
      end

      endpoints
    end

    # Routers unpacked straight into a url list: `[path(...), *router.urls]`.
    # Only the list's own elements count; one inside a nested
    # `include([...])` belongs to that include's mount.
    private def splatted_router_names(list_text : ::String) : Array(::String)
      return [] of ::String unless list_text.includes?(".urls")
      list_text = list_text.split("\n").join("\n") { |line| strip_python_comment(line) }
      open = list_text.index('[') || return [] of ::String
      close = list_text.rindex(']') || return [] of ::String
      return [] of ::String if close <= open
      split_python_arguments(list_text[(open + 1)...close]).compact_map do |element|
        element.strip.match(/\A\*\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\z/).try(&.[1])
      end.uniq!
    end

    private def extract_drf_direct_router_names(content : ::String) : Array(::String)
      router_names = [] of ::String
      scan_content = content.lines.reject(&.lstrip.starts_with?("#")).join("\n")

      scan_content.scan(/\burlpatterns\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      scan_content.scan(/\burlpatterns\s*\+=\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      scan_content.scan(/\burlpatterns\b[^\n]*\+\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      scan_content.scan(/\burlpatterns\s*\.\s*extend\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\s*\)/) do |match|
        router_names << match[1] if match.size == 2
      end

      router_names.uniq
    end

    private def extract_drf_router_endpoints(django_urls : DjangoUrls,
                                             mount_route : ::String,
                                             registration : DjangoDrfRegistration,
                                             package_map) : Array(Endpoint)
      resolved = resolve_django_view_reference(registration.view_ref, package_map)
      return [] of Endpoint unless resolved

      filepath, class_name = resolved
      route_base = join_url_parts(django_urls.prefix, mount_route, registration.prefix)
      extract_drf_viewset_endpoints(route_base, filepath, class_name, registration.trailing_slash)
    end

    private def extract_drf_router_endpoints_for_router(django_urls : DjangoUrls,
                                                        mount_route : ::String,
                                                        router_name : ::String,
                                                        drf_router_registrations : Hash(::String, Array(DjangoDrfRegistration)),
                                                        package_map : Hash(::String, Tuple(::String, Int32)),
                                                        import_aliases : Hash(::String, ::String),
                                                        route_path : PathInfo) : Array(Endpoint)
      endpoints = [] of Endpoint
      registrations = drf_router_registrations[router_name]? || [] of DjangoDrfRegistration
      registration_package_map = package_map
      router_path_info = route_path

      if registrations.empty?
        imported_router = package_map[router_name]?
        return endpoints unless imported_router

        imported_path, _imported_type = imported_router
        return endpoints unless File.exists?(imported_path)

        imported_content = read_file_content(imported_path)
        imported_registrations = extract_drf_router_registrations(imported_content)
        imported_router_name = import_aliases[router_name]? || router_name
        registrations = imported_registrations[imported_router_name]? || [] of DjangoDrfRegistration
        return endpoints if registrations.empty?

        registration_package_map = find_imported_modules(@django_base_path, imported_path, imported_content)
        router_path_info = PathInfo.new(imported_path)
      end

      registrations.each do |registration|
        extract_drf_router_endpoints(django_urls, mount_route, registration, registration_package_map).each do |endpoint|
          append_code_path(endpoint.details, route_path)
          append_code_path(endpoint.details, router_path_info)
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def extract_wrapped_view_reference(view : ::String) : ::String
      if as_view_match = view.match(/([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.as_view\s*\(/)
        return as_view_match[1]
      end
      # `login_required(views.drafts)` / `cache_page(60)(views.drafts)`: the
      # function view is the last call's sole argument.
      # ponytail: any `f(x)` unwraps to `x`, so a factory taking a view would too.
      if wrapped_match = view.match(/\(\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\)\s*\z/)
        return wrapped_match[1]
      end

      view
    end

    # The auth decorator wrapping `view` in the urlconf, read before
    # `extract_wrapped_view_reference` strips it; nil when there is none.
    private def urlconf_auth_wrapper(view : ::String) : ::String?
      view.match(URLCONF_AUTH_WRAPPER_RE).try(&.[1])
    end

    private def tag_urlconf_auth(endpoint : Endpoint, wrapper : ::String?) : Endpoint
      endpoint.add_tag(Tag.new("auth", "Protected by Django #{wrapper} in urlconf", TAGGER)) if wrapper
      endpoint
    end

    private def clean_python_reference(expression : ::String) : ::String
      reference = expression.strip
      reference = reference.split("#", 2)[0].strip
      return reference if reference.matches?(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/)

      ""
    end

    # A views module split once, with where each `def NAME(` / `class NAME(`
    # first matches: every URL pattern pointing into the module used to
    # re-split it and regex-search it from the top, so N views in one file
    # cost O(N * file).
    private record ViewFileIndex,
      content : ::String,
      lines : Array(::String),
      defs : Hash(::String, Tuple(Int32, Int32)),
      classes : Hash(::String, Tuple(Int32, Int32)) do
      # The file from a `{line, byte column}` position on, as lines.
      def tail(start : Tuple(Int32, Int32)) : Array(::String)
        line, column = start
        [lines[line].byte_slice(column)] + lines[(line + 1)..]
      end
    end

    VIEW_DEF_RE   = /(?:async\s+)?def\s+([^\s(]+)\s*\(/
    VIEW_CLASS_RE = /class\s+([^\s(:]+)\s*[\(:]/

    @view_file_index = Hash(::String, ViewFileIndex).new

    private def view_file_index(filepath : ::String) : ViewFileIndex
      @view_file_index[filepath] ||= begin
        content = read_file_content(filepath)
        lines = content.split("\n")
        defs = Hash(::String, Tuple(Int32, Int32)).new
        classes = Hash(::String, Tuple(Int32, Int32)).new
        lines.each_with_index do |line, index|
          if line.includes?("def")
            line.scan(VIEW_DEF_RE) { |m| defs.put_if_absent(m[1]) { {index, m.byte_begin(0)} } }
          end
          if line.includes?("class")
            line.scan(VIEW_CLASS_RE) { |m| classes.put_if_absent(m[1]) { {index, m.byte_begin(0)} } }
          end
        end
        ViewFileIndex.new(content, lines, defs, classes)
      end
    end

    # Extract endpoints from a given file
    def extract_endpoints_from_file(url : ::String, filepath : ::String, function_or_class_name : ::String, hops = 0)
      @logger.debug "Extracting endpoints from #{filepath}"

      endpoints = Array(Endpoint).new
      suspicious_http_methods = ["GET"]
      suspicious_params = Array(Param).new

      view_file = view_file_index(filepath)
      content = view_file.content
      content_lines = view_file.lines

      # Function Based View
      function_start = view_file.defs[function_or_class_name]?
      restricted = false
      unless function_start.nil?
        function_codeblock = parse_code_block(view_file.tail(function_start))
        unless function_codeblock.nil?
          lines = function_codeblock.split "\n"
          function_define_line = lines[0]
          lines = lines[1..]

          # Check the decorator stack above the def for HTTP methods.
          # Walk every contiguous decorator line (not just the one
          # directly above the def) so a method-restricting decorator
          # under, say, `@login_required` is still seen.
          # No earlier line can equal it: it would hold an earlier `def`.
          index = content_lines.index(function_define_line, function_start[0])
          unless index.nil?
            restricted_methods = nil
            index -= 1
            while index >= 0
              preceding_definition = content_lines[index]
              stripped = preceding_definition.lstrip
              index -= 1
              next if stripped.empty?                 # tolerate blank lines between stacked decorators
              break unless stripped.starts_with?("@") # only the contiguous decorator stack

              # `django.views.decorators.http` restrictors pin the exact
              # verb set and, crucially, drop the implicit GET default —
              # a `@require_POST` view answers 405 to GET, so emitting GET
              # was a false positive (and POST was missed entirely because
              # the bare `require_POST` token has no trailing delimiter for
              # the generic scan below).
              if methods = extract_django_require_methods(stripped)
                restricted_methods ||= [] of ::String
                methods.each { |m| restricted_methods << m unless restricted_methods.includes?(m) }
              else
                HTTP_METHODS_EXCLUDING_QUERY.each do |http_method_name|
                  method_name_match = preceding_definition.downcase.match DECORATOR_METHOD_NAME_REGEXES[http_method_name]
                  unless method_name_match.nil?
                    suspicious_http_methods << http_method_name.upcase
                  end
                end
              end
            end

            # A method-restricting decorator replaces the implicit GET.
            if rm = restricted_methods
              unless rm.empty?
                suspicious_http_methods = rm
                restricted = true
              end
            end
          end

          fold_python_continuations(lines).each do |line|
            # Check if line has 'request.method == "GET"' similar pattern
            if line.includes? "request.method"
              suspicious_code = line.split("request.method")[1].strip
              HTTP_METHODS.each do |http_method_name|
                method_name_match = suspicious_code.downcase.match REQUEST_METHOD_NAME_REGEXES[http_method_name]
                unless method_name_match.nil?
                  suspicious_http_methods << http_method_name.upcase
                end
              end
            end

            # A decorator-restricted view keeps its verb set: body accessors
            # (`request.data`, `request.POST`) must not widen it.
            scan_methods = restricted ? suspicious_http_methods.dup : suspicious_http_methods
            extract_params_from_line(line, scan_methods).each do |param|
              suspicious_params << param
            end
          end

          # Build once outside the per-method emit loop: a view function
          # routinely emits multiple endpoints (one per detected HTTP
          # method), but they all share the same handler body. The
          # codeblock starts at the `def` line, so `body_start_line` is
          # that line's 0-based index — derived from the char offset.
          body_start_line = function_start[0]
          definition_line = body_start_line + 1
          handler_callees = build_callees_from(
            function_codeblock,
            body_start_line,
            filepath,
            definition_base_path: @django_base_path,
            source: content
          )

          suspicious_http_methods.uniq.each do |http_method_name|
            details = Details.new(PathInfo.new(filepath, definition_line))
            endpoint = Endpoint.new(url, http_method_name, filter_params(http_method_name, suspicious_params), details)
            endpoint.handler = Handler.new(function_or_class_name, filepath, definition_line)
            handler_callees.each { |c| endpoint.push_callee(c) }
            endpoints << endpoint
          end

          return endpoints
        end
      end

      # Class Based View
      class_start = view_file.classes[function_or_class_name]?
      unless class_start.nil?
        class_lines = view_file.tail(class_start)
        class_codeblock = parse_python_class_codeblock(class_lines) || parse_code_block(class_lines)
        unless class_codeblock.nil?
          lines = class_codeblock.split "\n"
          class_define_line = lines[0]
          lines = lines[1..]

          # The bases a view inherits from the project itself: a DRF base
          # three mixins up still makes it an APIView.
          chain = drf_class_chain(filepath, function_or_class_name)
          chain_header = chain.empty? ? class_define_line : chain.join(" ", &.header)
          # `View.dispatch` (and DRF's, which extends it) serves only the
          # verbs the class has a handler for, so a plain `View` subclass
          # gets no implicit GET; only the verbs it defines.
          plain_view = chain.any? { |klass| python_class_bases(klass.header).any? { |base| base.split('.').last == "View" } }

          drf_generic_class = false
          if drf_methods = default_drf_generic_view_methods(chain_header)
            drf_generic_class = true
            suspicious_http_methods = drf_methods
          elsif plain_view
            suspicious_http_methods = [] of ::String
          else
            # Determine implicit HTTP methods based on class name
            if class_define_line.includes? "Form"
              suspicious_http_methods << "GET"
              suspicious_http_methods << "POST"
            elsif class_define_line.includes? "Delete"
              # Django's generic `DeleteView` serves the confirmation page
              # on GET and performs the delete on POST — it does NOT expose
              # the HTTP DELETE verb. Emitting DELETE here was a false
              # positive on every `class X(DeleteView)` (wagtail: 5). A view
              # that genuinely handles HTTP DELETE defines `def delete(self,
              # request, ...)`, which the explicit method-def scan below
              # already picks up, so real DELETE endpoints are unaffected.
              suspicious_http_methods << "POST"
            elsif class_define_line.includes? "Create"
              suspicious_http_methods << "POST"
            elsif class_define_line.includes? "Update"
              suspicious_http_methods << "POST"
            end
          end

          body_start_line = class_start[0]
          class_definition_line = body_start_line + 1
          method_callees = Hash(String, Array(Callee)).new
          method_lines = Hash(String, Int32).new
          common_params = Array(Param).new
          method_params = Hash(String, Array(Param)).new do |hash, key|
            hash[key] = [] of Param
          end
          current_http_methods : Array(String)? = nil

          # Check HTTP methods in class methods. Params are read off the
          # folded view so a wrapped `request.GET.get(` call still counts.
          folded_lines = fold_python_continuations(lines)
          lines.each_with_index do |line, offset|
            method_function_match = line.match(REGEX_CBV_METHOD_DEF)
            any_method_function_match = line.match(/\s+(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/)
            unless any_method_function_match.nil?
              current_http_methods = nil
            end

            if method_function_match
              method_name = method_function_match[1].upcase
              current_http_methods = [method_name]
              suspicious_http_methods << method_name
              method_lines[method_name] = body_start_line + offset + 2

              if codeblock = parse_code_block(lines[offset..])
                method_callees[method_name] = build_callees_from(
                  codeblock,
                  body_start_line + offset + 1,
                  filepath,
                  definition_base_path: @django_base_path,
                  source: content
                )
                method_params[method_name].concat drf_serializer_params(codeblock, filepath, chain)
              end
            elsif drf_generic_class && any_method_function_match && (drf_methods = drf_generic_action_http_methods(any_method_function_match[1]))
              current_http_methods = drf_methods
              drf_methods.each do |method_name|
                next unless suspicious_http_methods.includes?(method_name)
                method_lines[method_name] ||= body_start_line + offset + 2
              end
            end

            if method_names = current_http_methods
              scan_methods = method_names.dup
              extract_params_from_line(folded_lines[offset], scan_methods).each do |param|
                method_names.each do |mapped_method_name|
                  next unless suspicious_http_methods.includes?(mapped_method_name)
                  method_params[mapped_method_name] << param
                end
              end
            else
              extract_params_from_line(folded_lines[offset], suspicious_http_methods).each do |param|
                common_params << param
              end
            end
          end

          # A verb handler the view inherits from a project base class is
          # served by that base's method: `post` on a shared mixin.
          method_owners = Hash(String, DrfClass).new
          chain.skip(1).each do |klass|
            klass.codeblock.split("\n").each_with_index do |line, offset|
              next unless inherited = line.match(REGEX_CBV_METHOD_DEF)
              method_name = inherited[1].upcase
              next if method_lines.has_key?(method_name)
              suspicious_http_methods << method_name
              method_lines[method_name] = klass.line_index + offset + 1
              method_owners[method_name] = klass
            end
          end

          if declared = declared_http_method_names(view_file, class_codeblock, class_define_line)
            suspicious_http_methods = declared
          end

          suspicious_http_methods = ["GET"] if suspicious_http_methods.empty? && plain_view && !drf_generic_class
          if suspicious_http_methods.empty?
            return endpoints
          end

          suspicious_http_methods.uniq.each do |http_method_name|
            owner = method_owners[http_method_name]?
            source_path = owner.try(&.filepath) || filepath
            definition_line = method_lines[http_method_name]? || class_definition_line
            details = Details.new(PathInfo.new(source_path, definition_line))
            endpoint_params = common_params + (method_params[http_method_name]? || [] of Param)
            endpoint = Endpoint.new(url, http_method_name, filter_params(http_method_name, endpoint_params), details)
            # A verb with no body in the project (served by the framework
            # base, `TemplateView.get`) has no handler to point at.
            if method_lines.has_key?(http_method_name)
              endpoint.handler = Handler.new(owner.try(&.name) || function_or_class_name, source_path, definition_line)
            end
            if callees = method_callees[http_method_name]?
              callees.each { |c| endpoint.push_callee(c) }
            end
            endpoints << endpoint
          end

          return endpoints
        end
      end

      # Neither defined here: follow a module-level re-export to the real
      # view. The hop bound also breaks a re-export cycle.
      if hops < 3 && (target = resolve_view_reexport(filepath, content, function_or_class_name))
        return extract_endpoints_from_file(url, target[0], target[1], hops + 1)
      end

      # Default to GET method
      [Endpoint.new(url, "GET", Details.new(PathInfo.new(filepath)))]
    end

    # The verbs `View.dispatch` lets through when the class (or a base
    # declared in the same file) sets `http_method_names`; every other
    # verb gets a 405, so the declaration replaces whatever the class name
    # and `def` scan implied. `BasketAddView(FormView)` with `["post"]`
    # has no GET. Nil when nothing in reach declares it.
    # ponytail: one level of same-file bases; a mixin from another module
    # that sets it is not read. HEAD/OPTIONS/TRACE are no surface of their
    # own and are dropped.
    private def declared_http_method_names(view_file : ViewFileIndex, class_codeblock : ::String,
                                           class_define_line : ::String, depth = 0) : Array(::String)?
      if allowed = class_codeblock.match(DRF_HTTP_METHOD_NAMES_RE)
        return allowed[1].scan(/['"]([A-Za-z]+)['"]/).map(&.[1].upcase) & %w[GET POST PUT PATCH DELETE]
      end
      return if depth > 0
      bases = class_define_line.match(/\(([^)]*)\)/).try(&.[1]) || return
      bases.split(',').each do |base|
        base_start = view_file.classes[base.strip]? || next
        base_lines = view_file.tail(base_start)
        base_codeblock = parse_python_class_codeblock(base_lines) || parse_code_block(base_lines) || next
        if declared = declared_http_method_names(view_file, base_codeblock, base_codeblock.lines.first? || "", depth + 1)
          return declared
        end
      end
      nil
    end

    private def default_drf_generic_view_methods(class_define_line : ::String) : Array(::String)?
      # DRF's and simplejwt's token views are APIViews that define only `post`.
      return ["POST"] if class_define_line.matches?(DRF_TOKEN_VIEW_RE)
      return unless class_define_line.includes?("APIView")

      if class_define_line.includes?("RetrieveUpdateDestroyAPIView")
        ["GET", "PUT", "PATCH", "DELETE"]
      elsif class_define_line.includes?("RetrieveUpdateAPIView")
        ["GET", "PUT", "PATCH"]
      elsif class_define_line.includes?("RetrieveDestroyAPIView")
        ["GET", "DELETE"]
      elsif class_define_line.includes?("ListCreateAPIView")
        ["GET", "POST"]
      elsif class_define_line.includes?("RetrieveAPIView")
        ["GET"]
      elsif class_define_line.includes?("ListAPIView")
        ["GET"]
      elsif class_define_line.includes?("CreateAPIView")
        ["POST"]
      elsif class_define_line.includes?("UpdateAPIView")
        ["PUT", "PATCH"]
      elsif class_define_line.includes?("DestroyAPIView")
        ["DELETE"]
      else
        [] of ::String
      end
    end

    private def drf_generic_action_http_methods(method_name : ::String) : Array(::String)?
      case method_name
      when "list", "retrieve"
        ["GET"]
      when "create"
        ["POST"]
      when "update"
        ["PUT", "PATCH"]
      when "partial_update"
        ["PATCH"]
      when "destroy"
        ["DELETE"]
      end
    end

    # One class of a ViewSet's in-repo inheritance chain.
    private record DrfClass, filepath : ::String, name : ::String, codeblock : ::String,
      header : ::String, line_index : Int32

    # The class and the in-repo bases it inherits from, nearest first: a
    # depth-first walk of the bases in declaration order, which is Python's
    # MRO for the one-concrete-base-per-branch shape ViewSets use. A base
    # that resolves to no scanned file (DRF's own) ends its branch.
    @class_chains = Hash(Tuple(::String, ::String), Array(DrfClass)).new
    @imported_symbols = Hash(::String, Hash(::String, Tuple(::String, ::String))).new

    private def drf_class_chain(filepath : ::String, class_name : ::String) : Array(DrfClass)
      @class_chains[{filepath, class_name}] ||= collect_class_chain(filepath, class_name, Set(::String).new, 0)
    end

    private def collect_class_chain(filepath : ::String, class_name : ::String,
                                    seen : Set(::String), depth : Int32) : Array(DrfClass)
      chain = [] of DrfClass
      return chain if depth > 6 || !seen.add?("#{filepath}:#{class_name}")
      view_file = view_file_index(filepath)
      start = view_file.classes[class_name]? || return chain
      codeblock = parse_python_class_codeblock(view_file.tail(start)) || return chain
      header = extract_python_definition_header(codeblock.split("\n"))
      chain << DrfClass.new(filepath, class_name, codeblock, header, start[0])

      python_class_bases(header).each do |base|
        if target = resolve_python_class(filepath, base)
          chain.concat collect_class_chain(target[0], target[1], seen, depth + 1)
        end
      end
      chain
    end

    # `{file, class name}` for a class `name` refers to in `filepath`: one
    # declared there, or one imported into it (`Base`, `mixins.Base`).
    private def resolve_python_class(filepath : ::String, name : ::String) : Tuple(::String, ::String)?
      view_file = view_file_index(filepath)
      return {filepath, name} if view_file.classes.has_key?(name)
      symbols = @imported_symbols[filepath] ||= Noir::ImportGraph::Python.find_imported_symbols(@django_base_path, filepath, view_file.content)
      head, _, attr = name.rpartition('.')
      target = if head.empty?
                 symbols[name]?
               elsif imported = symbols[head]?
                 {imported[0], imported[1].empty? ? attr : ""}
               end
      return unless target
      return if target[1].empty? || !File.file?(target[0])
      target
    end

    # `XSerializer(data=request.data)` / `self.get_serializer(data=...)`.
    SERIALIZER_DATA_RE = /\b([A-Za-z_][A-Za-z0-9_.]*)\s*\(\s*(?:[^()]*?,\s*)?data\s*=\s*[^,()]*\brequest\.data\b/
    # A declared serializer field: `name = serializers.CharField(`.
    SERIALIZER_FIELD_RE = /^(\s+)([a-z_][a-z0-9_]*)\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Z][A-Za-z0-9_]*(?:Field|Serializer))\s*\(/

    # Body fields a handler reads through the DRF serializer it hands
    # `request.data`: the fields that serializer class (or a project base)
    # declares. `get_serializer` means the view's `serializer_class`.
    # ponytail: declared fields only; a ModelSerializer's `Meta.fields`
    # model columns are not resolved.
    private def drf_serializer_params(codeblock : ::String, filepath : ::String, view_chain : Array(DrfClass)) : Array(Param)
      params = [] of Param
      return params unless codeblock.includes?("request.data")
      codeblock.scan(SERIALIZER_DATA_RE) do |call|
        name = call[1]
        if name.ends_with?("get_serializer")
          name = view_chain.compact_map(&.codeblock.match(/^\s+serializer_class\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)\s*$/m).try(&.[1])).first? || next
        end
        target = resolve_python_class(filepath, name) || next
        drf_class_chain(target[0], target[1]).each do |klass|
          body = klass.codeblock.split("\n")[1..]
          level = body.compact_map { |line| line.size - line.lstrip.size unless line.strip.empty? }.min? || next
          body.each_with_index do |line, index|
            field = line.match(SERIALIZER_FIELD_RE) || next
            next unless field[1].size == level
            next if field[3] == "SerializerMethodField"
            next if python_call_span(body, index, line)[0].matches?(/\bread_only\s*=\s*True\b/)
            params << Param.new(field[2], "", "form") unless params.any? { |param| param.name == field[2] }
          end
        end
      end
      params
    end

    # `class X(A, mixins.B, C[Model], metaclass=M):` → ["A", "mixins.B", "C"].
    private def python_class_bases(header : ::String) : Array(::String)
      bases = [] of ::String
      open = header.byte_index('(') || return bases
      close = python_close_paren_byte(header.to_slice, open) || return bases
      split_python_arguments(header.byte_slice(open + 1, close - open - 1)).each do |base|
        base = base.strip
        next if base.includes?('=')
        base = base.sub(/\[[\s\S]*\z/, "").strip
        bases << base if base.matches?(/\A[A-Za-z_][A-Za-z0-9_.]*\z/)
      end
      bases
    end

    # Each method of a class body with the decorator source stacked above
    # it, as `{name, decorators, 0-based line within body_lines}`.
    private def each_python_class_method(body_lines : Array(::String), &)
      level = body_lines.compact_map do |line|
        stripped = line.lstrip
        line.size - stripped.size if stripped.starts_with?('@') || stripped.matches?(/\A(?:async\s+)?def\s/)
      end.min?
      return unless level

      pending = [] of ::String
      depth = 0
      body_lines.each_with_index do |line, offset|
        if depth > 0
          pending << line
          depth += python_paren_delta(line)
          next
        end
        stripped = line.lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = line.size - stripped.size
        if indent == level && stripped.starts_with?('@')
          pending << line
          depth = python_paren_delta(line)
          next
        end
        if indent == level && (method = stripped.match(/\A(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/))
          yield method[1], pending.join("\n"), offset
        end
        pending.clear if indent <= level
      end
    end

    # The argument text of an `@action(...)` decorator in `decorators`.
    private def drf_action_decorator_args(decorators : ::String) : ::String?
      call = decorators.match(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)?action\s*\(/) || return
      open = call.byte_end(0) - 1
      close = python_close_paren_byte(decorators.to_slice, open) || return
      decorators.byte_slice(open + 1, close - open - 1)
    end

    private def extract_drf_viewset_endpoints(route_base : ::String, filepath : ::String, class_name : ::String,
                                              trailing_slash : Bool = true) : Array(Endpoint)
      endpoints = [] of Endpoint
      chain = drf_class_chain(filepath, class_name)
      return endpoints if chain.empty?

      own = chain.first
      class_definition_line = own.line_index + 1
      lookup_param = chain.compact_map { |klass| drf_lookup_param(klass.codeblock) }.first? || "pk"
      # Mixins anywhere up the chain decide which standard actions exist.
      actions = default_drf_viewset_actions(chain.join(" ", &.header))

      # Python resolves a method on the nearest class that defines it, so
      # the first definition of a name wins and a base's is shadowed.
      defined = Set(::String).new
      extra_actions = Hash(::String, DjangoDrfAction).new
      mappings = [] of Tuple(::String, ::String, ::String, DrfClass, Array(::String), Int32)
      chain.each do |klass|
        body_lines = klass.codeblock.split("\n")[1..]
        each_python_class_method(body_lines) do |method_name, decorators, offset|
          next unless defined.add?(method_name)

          method_actions = [] of DjangoDrfAction
          if args = drf_action_decorator_args(decorators)
            detail = args.matches?(/\bdetail\s*=\s*True\b/)
            # DRF: `url_path` defaults to the method name itself; only
            # `url_name` (the reverse() name) swaps `_` for `-`.
            url_path = normalize_django_route(extract_drf_action_url_path(args) || method_name)
            method_actions = extract_drf_action_methods(args).map { |verb| DjangoDrfAction.new(method_name, verb, detail, url_path) }
            extra_actions[method_name] = method_actions.first unless method_actions.empty?
          elsif mapping = decorators.match(/@([A-Za-z_][A-Za-z0-9_]*)\.mapping\.(get|post|put|patch|delete)\b/)
            mappings << {mapping[1], mapping[2].upcase, method_name, klass, body_lines, offset}
            next
          elsif action = drf_action_for_method(method_name)
            method_actions << action
          end

          method_actions.each do |drf_action|
            fill_drf_action(drf_action, klass, body_lines, offset, chain)
            actions.reject! { |existing| existing.method == drf_action.method && existing.detail == drf_action.detail && existing.path == drf_action.path }
            actions << drf_action
          end
        end
      end

      # `@download.mapping.post def upload(...)`: another verb on the
      # `download` action's route, served by `upload`.
      mappings.each do |target, verb, method_name, klass, body_lines, offset|
        base = extra_actions[target]? || next
        drf_action = DjangoDrfAction.new(method_name, verb, base.detail, base.path)
        fill_drf_action(drf_action, klass, body_lines, offset, chain)
        actions.reject! { |existing| existing.method == verb && existing.detail == base.detail && existing.path == base.path }
        actions << drf_action
      end

      # View.dispatch refuses any verb missing from `http_method_names`.
      if allowed = chain.compact_map(&.codeblock.match(DRF_HTTP_METHOD_NAMES_RE)).first?
        verbs = allowed[1].scan(/['"]([A-Za-z]+)['"]/).map(&.[1].upcase)
        actions.select! { |action| verbs.includes?(action.method) }
      end

      actions.each do |action|
        endpoint_path = drf_action_path(route_base, lookup_param, action, trailing_slash)
        params = filter_params(action.method, action.params)
        params << Param.new(lookup_param, "", "path") if action.detail
        params = dedupe_params(params)
        source_path = action.filepath || own.filepath
        details = Details.new(PathInfo.new(source_path, action.definition_line || class_definition_line))
        endpoint = Endpoint.new(endpoint_path, action.method, params, details)
        # A standard action inherited from DRF itself has no body in the
        # project to point at, so it gets no handler.
        if (handler_name = action.handler) && (line = action.definition_line)
          endpoint.handler = Handler.new(handler_name, source_path, line)
        end
        action.callees.each { |callee| endpoint.push_callee(callee) }
        endpoints << endpoint
      end

      endpoints
    end

    # Point `drf_action` at the method `offset` lines into `klass`'s body:
    # its definition site, handler name, params and callees.
    private def fill_drf_action(drf_action : DjangoDrfAction, klass : DrfClass, body_lines : Array(::String), offset : Int32,
                                chain : Array(DrfClass))
      drf_action.definition_line = klass.line_index + offset + 2
      drf_action.filepath = klass.filepath
      drf_action.handler = "#{klass.name}.#{drf_action.name}"
      codeblock = parse_code_block(body_lines[offset..]) || return
      fold_python_continuations(codeblock.split("\n")).each do |body_line|
        extract_params_from_line(body_line, [drf_action.method]).each do |param|
          drf_action.params << param
        end
      end
      drf_action.params.concat drf_serializer_params(codeblock, klass.filepath, chain)
      drf_action.callees = build_callees_from(
        codeblock,
        klass.line_index + offset + 1,
        klass.filepath,
        definition_base_path: @django_base_path,
        source: read_file_content(klass.filepath)
      )
    end

    private def default_drf_viewset_actions(class_define_line : ::String) : Array(DjangoDrfAction)
      actions = [] of DjangoDrfAction

      if class_define_line.includes?("ReadOnlyModelViewSet")
        actions << DjangoDrfAction.new("list", "GET", false, "")
        actions << DjangoDrfAction.new("retrieve", "GET", true, "")
      elsif class_define_line.includes?("ModelViewSet")
        actions << DjangoDrfAction.new("list", "GET", false, "")
        actions << DjangoDrfAction.new("create", "POST", false, "")
        actions << DjangoDrfAction.new("retrieve", "GET", true, "")
        actions << DjangoDrfAction.new("update", "PUT", true, "")
        actions << DjangoDrfAction.new("partial_update", "PATCH", true, "")
        actions << DjangoDrfAction.new("destroy", "DELETE", true, "")
      end

      actions << DjangoDrfAction.new("list", "GET", false, "") if class_define_line.includes?("ListModelMixin")
      actions << DjangoDrfAction.new("create", "POST", false, "") if class_define_line.includes?("CreateModelMixin")
      actions << DjangoDrfAction.new("retrieve", "GET", true, "") if class_define_line.includes?("RetrieveModelMixin")
      actions << DjangoDrfAction.new("update", "PUT", true, "") if class_define_line.includes?("UpdateModelMixin")
      actions << DjangoDrfAction.new("partial_update", "PATCH", true, "") if class_define_line.includes?("UpdateModelMixin")
      actions << DjangoDrfAction.new("destroy", "DELETE", true, "") if class_define_line.includes?("DestroyModelMixin")

      actions
    end

    private def drf_action_for_method(method_name : ::String) : DjangoDrfAction?
      case method_name
      when "list"
        DjangoDrfAction.new(method_name, "GET", false, "")
      when "create"
        DjangoDrfAction.new(method_name, "POST", false, "")
      when "retrieve"
        DjangoDrfAction.new(method_name, "GET", true, "")
      when "update"
        DjangoDrfAction.new(method_name, "PUT", true, "")
      when "partial_update"
        DjangoDrfAction.new(method_name, "PATCH", true, "")
      when "destroy"
        DjangoDrfAction.new(method_name, "DELETE", true, "")
      end
    end

    private def extract_python_definition_header(lines : Array(::String)) : ::String
      header = [] of ::String
      delta = 0

      lines.each do |line|
        header << line.strip
        delta += python_paren_delta(line)
        break if delta <= 0 && line.includes?(":")
      end

      header.join(" ")
    end

    private def parse_python_class_codeblock(lines : Array(::String)) : ::String?
      return if lines.empty?

      class_indent = lines[0].size - lines[0].lstrip.size
      collected = [] of ::String
      delta = 0
      index = 0
      header_closed = false

      while index < lines.size
        line = lines[index]
        collected << line
        delta += python_paren_delta(line)
        index += 1

        if delta <= 0 && line.includes?(":")
          header_closed = true
          break
        end
      end
      return unless header_closed

      while index < lines.size
        line = lines[index]
        if line.strip.empty?
          collected << line
          index += 1
          next
        end

        indent = line.size - line.lstrip.size
        break if indent <= class_indent

        collected << line
        index += 1
      end

      collected.join("\n").strip
    end

    private def extract_drf_action_methods(args : ::String) : Array(::String)
      methods_match = args.match(/\bmethods\s*=\s*(\[[^\]]*\]|\([^\)]*\)|[rf]?['"][^'"]+['"])/)
      return ["GET"] unless methods_match

      methods = methods_match[1].scan(/[rf]?['"]([^'"]+)['"]/).map(&.[1].upcase)
      methods.empty? ? ["GET"] : methods
    end

    private def extract_drf_action_url_path(args : ::String) : ::String?
      url_path_match = args.match(/\burl_path\s*=\s*[rf]?['"]([^'"]+)['"]/)
      url_path_match ? url_path_match[1] : nil
    end

    private def drf_lookup_param(class_codeblock : ::String) : ::String?
      class_codeblock.match(/\blookup_url_kwarg\s*=\s*[rf]?['"]([^'"]+)['"]/).try(&.[1]) ||
        class_codeblock.match(/\blookup_field\s*=\s*[rf]?['"]([^'"]+)['"]/).try(&.[1])
    end

    private def drf_action_path(route_base : ::String, lookup_param : ::String, action : DjangoDrfAction,
                                trailing_slash : Bool) : ::String
      parts = [route_base]
      parts << "{#{lookup_param}}" if action.detail
      parts << action.path unless action.path.empty?
      path = join_url_parts(parts)
      trailing_slash ? ensure_trailing_slash(path) : path
    end

    private def join_url_parts(parts : Array(::String)) : ::String
      cleaned = parts.map(&.strip).reject(&.empty?)
      return "/" if cleaned.empty?

      "/#{cleaned.join("/")}".gsub(/\/+/, "/")
    end

    private def join_url_parts(*parts : ::String) : ::String
      join_url_parts(parts.to_a)
    end

    private def ensure_trailing_slash(path : ::String) : ::String
      return "/" if path.empty?
      path.ends_with?("/") ? path : "#{path}/"
    end

    private def dedupe_params(params : Array(Param)) : Array(Param)
      deduped = [] of Param
      params.each do |param|
        next if deduped.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
        deduped << param
      end

      deduped
    end

    private def resolve_django_view_reference(view_ref : ::String, package_map) : Tuple(::String, ::String)?
      dotted_as_names_split = view_ref.split(".")

      dotted_as_names_split.each_with_index do |name, index|
        next unless package_map.has_key?(name)

        filepath, package_type = package_map[name]
        # The import graph records a package *directory* import with an
        # empty file path (`find_imported_package` only ever fills `py_path`
        # for a module file). Handing that back as a resolution made the
        # callers read `""` and abort the entire analyzer with "Error opening
        # file with mode 'r': ''" — one unresolvable view in one urlconf took
        # every Django endpoint in the project down with it. The sibling
        # `resolve_django_view_target` has always guarded this; treat an
        # empty path as "not resolved" here too and let the caller fall back
        # to the plain GET endpoint.
        next if filepath.empty?

        function_or_class_name = name
        if package_type == PackageType::FILE && index + 1 < dotted_as_names_split.size
          function_or_class_name = dotted_as_names_split[index + 1]
        end

        return {filepath, function_or_class_name}
      end

      nil
    end

    private def append_code_path(details : Details, path_info : PathInfo)
      return if details.code_paths.any? { |existing| existing == path_info }
      details.add_path(path_info)
    end

    # Map a `django.views.decorators.http` restrictor decorator line to
    # the exact HTTP verbs it allows, or nil when the decorator isn't a
    # method restrictor. These decorators define the allowed-method set
    # authoritatively (everything else 405s), so the caller uses the
    # result to REPLACE the implicit GET default rather than add to it.
    private def extract_django_require_methods(decorator : ::String) : Array(::String)?
      if match = decorator.match(/@\s*(?:\w+\.)*require_http_methods\s*\(\s*(?:request_method_list\s*=\s*)?[\[(]([^\])]*)[\])]/)
        methods = [] of ::String
        match[1].scan(/[rf]?['"]([A-Za-z]+)['"]/) do |m|
          verb = m[1].upcase
          methods << verb if HTTP_METHODS.any? { |hm| hm.upcase == verb }
        end
        return methods.empty? ? nil : methods
      end

      # `@require_POST` / `@require_GET` — verb embedded in the name.
      if match = decorator.match(/@\s*(?:\w+\.)*require_(GET|POST|HEAD)\b/i)
        return [match[1].upcase]
      end

      # `@require_safe` allows GET + HEAD.
      if decorator.matches?(/@\s*(?:\w+\.)*require_safe\b/)
        return ["GET", "HEAD"]
      end

      # DRF `@api_view([...])` / `@api_view(http_method_names=[...])`:
      # the list is authoritative and a bare `@api_view()` means GET only.
      if match = decorator.match(/@\s*(?:\w+\.)*api_view\b\s*(?:\((.*)\))?/)
        args = match[1]?.to_s.strip
        return ["GET"] if args.empty?
        if list = args.match(/\A(?:http_method_names\s*=\s*)?[\[(]([^\])]*)[\])]/)
          methods = [] of ::String
          list[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
            verb = m[1].upcase
            methods << verb if HTTP_METHODS.any? { |hm| hm.upcase == verb }
          end
          return methods.empty? ? nil : methods
        end
      end

      nil
    end

    # Extract parameters from a line of code
    def extract_params_from_line(line : ::String, endpoint_methods : Array(::String))
      suspicious_params = Array(Param).new

      if line.includes? "request."
        REQUEST_PARAM_FIELD_PATTERNS.each do |field_pattern|
          field_name, field_methods, param_type, bracket_re, get_re = field_pattern
          matches = line.scan(bracket_re)
          if matches.empty?
            matches = line.scan(get_re)
          end

          unless matches.empty?
            matches.each do |match|
              next if match.size != 2
              param_name = match[1]
              if field_name == "META"
                header_name = meta_header_name(param_name)
                next unless header_name
                param_name = header_name
              end

              # If a specific parameter is found, allow the corresponding methods
              unless field_methods.nil?
                field_methods.each do |field_method|
                  if !endpoint_methods.includes? field_method
                    endpoint_methods << field_method
                  end
                end
              end

              suspicious_params << Param.new(param_name, "", param_type)
            end
          end
        end
      end

      if line.includes? "form.cleaned_data"
        matches = line.scan(/form\.cleaned_data\[[rf]?['"]([^'"]*)['"]\]/)
        if matches.empty?
          matches = line.scan(/form\.cleaned_data\.get\([rf]?['"]([^'"]*)['"]/)
        end

        unless matches.empty?
          matches.each do |match|
            next if match.size != 2
            suspicious_params << Param.new(match[1], "", "form")
          end
        end
      end

      suspicious_params
    end

    # A `request.META` key as the header the client sends: the WSGI environ
    # spells `X-Forwarded-For` as `HTTP_X_FORWARDED_FOR`, and Content-Type
    # and Content-Length without the prefix. Any other key (REMOTE_ADDR,
    # SERVER_NAME, ...) is server state, not a request header: nil.
    private def meta_header_name(key : ::String) : ::String?
      return key.downcase.tr("_", "-") if key.in?("CONTENT_TYPE", "CONTENT_LENGTH")
      http_header_name(key)
    end

    # Filter parameters based on HTTP method
    def filter_params(method : ::String, params : Array(Param))
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_supported_param = false
        support_methods = REQUEST_PARAM_TYPE_MAP.fetch(param.param_type, nil)
        if support_methods.nil?
          is_supported_param = true
        else
          support_methods.each do |support_method|
            if upper_method == support_method.upcase
              is_supported_param = true
            end
          end
        end

        filtered_params.each do |filtered_param|
          if filtered_param.name == param.name && filtered_param.param_type == param.param_type
            is_supported_param = false
            break
          end
        end

        if is_supported_param
          filtered_params << param
        end
      end

      filtered_params
    end

    module PackageType
      FILE = 0
      CODE = 1
    end

    struct DjangoUrls
      include JSON::Serializable
      property prefix, filepath, basepath

      def initialize(@prefix : ::String, @filepath : ::String, @basepath : ::String)
        if !File.directory? @basepath
          raise "The basepath for DjangoUrls (#{@basepath}) does not exist or is not a directory."
        end
      end
    end

    struct DjangoView
      include JSON::Serializable
      property prefix, filepath, name

      def initialize(@prefix : ::String, @filepath : ::String, @name : ::String)
        if !File.directory? @filepath
          raise "The filepath for DjangoView (#{@filepath}) does not exist."
        end
      end
    end

    struct DjangoDrfRegistration
      property prefix, view_ref, trailing_slash

      def initialize(@prefix : ::String, @view_ref : ::String, @trailing_slash : Bool = true)
      end
    end

    class DjangoDrfAction
      property name, method, detail, path, params, definition_line, callees, filepath, handler

      @definition_line : Int32?
      @filepath : ::String?
      @handler : ::String?

      def initialize(@name : ::String,
                     @method : ::String,
                     @detail : Bool,
                     @path : ::String,
                     @params = [] of Param,
                     @definition_line = nil,
                     @callees = [] of Callee)
      end
    end
  end
end
