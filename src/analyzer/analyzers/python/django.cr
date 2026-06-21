require "../../engines/python_engine"
require "json"

module Analyzer::Python
  class Django < PythonEngine
    # Base path for the Django project
    @django_base_path : ::String = ""
    @visited_url_paths = Hash(String, Bool).new
    @django_app_config_path_cache = Hash(::String, ::String).new
    @visited_app_config_paths = Set(::String).new

    # Regular expressions for extracting Django URL configurations
    REGEX_ROOT_URLCONF = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
    REGEX_INCLUDE_URLS = /\binclude\s*\(\s*r?['"]([^'"\\]*)['"]/

    # `def get(...)` / `async def post(...)` method heads in class-based
    # views. Precompiled — an interpolated literal would be recompiled on
    # every line of every CBV class body.
    REGEX_CBV_METHOD_DEF = /\s+(?:async\s+)?def\s+(#{HTTP_METHODS.join("|")})\s*\(/

    # Map request parameters to their respective fields
    REQUEST_PARAM_FIELD_MAP = {
      "GET"          => {["GET"], "query"},
      "POST"         => {["POST"], "form"},
      "COOKIES"      => {nil, "cookie"},
      "META"         => {nil, "header"},
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
        Regex.new("request\\.#{field_name}\\.get\\([rf]?['\"]([^'\"]*)['\"]"),
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

      # Fall back to scanning `urls.py` modules directly when the
      # ROOT_URLCONF-anchored pass above produced nothing. Reusable
      # Django apps and libraries (Wagtail, DRF, …) — and any project
      # scanned at the app level — ship `urls.py` files with
      # `urlpatterns` but no project `settings.py` declaring
      # `ROOT_URLCONF`, so the anchored pass finds no root and the
      # whole app silently maps to zero endpoints. Treating each
      # unvisited, non-test `urls.py` as its own routing root recovers
      # those routes (app-relative, since there is no host-project
      # mount prefix to apply). Gated on an empty result so every
      # project that DOES expose a ROOT_URLCONF keeps its fully
      # prefixed paths and sees no behavior change.
      if endpoints.empty?
        extract_endpoints_from_orphan_urlconfs.each do |endpoint|
          endpoints << endpoint
        end
      end

      # Find static files
      begin
        base_paths.each do |base|
          static_prefix = base.ends_with?("/") ? "#{base}static/" : "#{base}/static/"
          get_files_by_prefix(static_prefix).each do |file|
            relative_path = file.sub(static_prefix, "")
            endpoints << Endpoint.new("/#{relative_path}", "GET")
          end
        end
      rescue e
        logger.debug e
      end

      endpoints
    end

    # Treat every unvisited, non-test `urls.py` (or `urls/` package
    # module) carrying a `urlpatterns` as its own routing root. Used
    # only as a fallback when no ROOT_URLCONF anchor exists, so the
    # paths are app-relative — there is no host project to supply a
    # mount prefix. `extract_endpoints` marks each file (and anything
    # it `include()`s) visited, so a module pulled in by another is
    # not processed twice.
    private def extract_endpoints_from_orphan_urlconfs : Array(Endpoint)
      endpoints = [] of Endpoint

      candidates = all_files.select do |file|
        next false unless file.ends_with?(".py")
        next false if file.includes?("/site-packages/")
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
      @visited_url_paths.each_key { |key| visited << File.expand_path(key) }

      candidates.each do |file|
        candidate_base_path = base_path_for(file)
        @django_base_path = candidate_base_path
        expanded = File.expand_path(file)
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
        @visited_url_paths.each_key { |key| visited << File.expand_path(key) }
      end

      endpoints
    end

    # Find all root Django URLs
    def find_root_django_urls : Array(DjangoUrls)
      root_django_urls_list = [] of DjangoUrls
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      WaitGroup.wait do |wg|
        # Producer — tracked by the WaitGroup
        wg.spawn do
          all_files.each { |file| channel.send(file) }
          channel.close
        end

        @options["concurrency"].to_s.to_i.times do
          wg.spawn do
            loop do
              begin
                file = channel.receive?
                break if file.nil?
                next if File.directory?(file)
                next if file.includes?("/site-packages/")
                # Skip Python test files: each Django test app under
                # `tests/<feature>/` carries its own `ROOT_URLCONF`
                # the analyzer would otherwise treat as a real Django
                # project root. Django's own repo contributes ~720
                # such phantom endpoints. Standard test conventions
                # (`tests/` dir, `tests.py`, `test_*.py`, `*_test.py`)
                # are unambiguous in Python codebases.
                current_base_path = base_path_for(file)
                next if PythonEngine.python_test_path?(file, current_base_path)
                next unless django_settings_path?(file)
                if file.ends_with? ".py"
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
              rescue File::NotFoundError
                logger.debug "File not found: #{file}"
              end
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

      paths = [] of ::String
      Dir.glob("#{escape_glob_path(search_dir)}/**/#{relative_path}") do |filepath|
        paths << filepath
      end
      paths.uniq
    end

    # Extract endpoints from a Django URL configuration file
    def extract_endpoints(django_urls : DjangoUrls) : Array(Endpoint)
      logger.debug "Extracting endpoints from #{django_urls.filepath}"
      endpoints = [] of Endpoint
      url_base_path = File.dirname(django_urls.filepath)
      @visited_url_paths[django_urls.filepath] = true

      file = File.open(django_urls.filepath, encoding: "utf-8", invalid: :skip)
      content = file.gets_to_end
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
        extract_route_mappings(urlpatterns_content).each do |route_mapping|
          route, view = route_mapping
          route = normalize_django_route(route)
          url = "/#{django_urls.prefix}/#{route}".gsub(/\/+/, "/")
          new_django_urls = nil
          view.scan(REGEX_INCLUDE_URLS) do |include_pattern_match|
            # Detect new URL configurations
            next if include_pattern_match.size != 2
            new_route_path = "#{@django_base_path}/#{include_pattern_match[1].gsub(".", "/")}.py"

            if File.exists?(new_route_path)
              new_django_urls = DjangoUrls.new("#{django_urls.prefix}#{route}", new_route_path, django_urls.basepath)
              unless @visited_url_paths.has_key? new_django_urls.filepath
                extract_endpoints(new_django_urls).each do |endpoint|
                  append_code_path(endpoint.details, PathInfo.new(new_route_path))
                  endpoints << endpoint
                end
              end
            end
          end
          next if new_django_urls

          if app_config_path = resolve_django_app_config_include_path(view, app_config_refs)
            extract_endpoints_from_django_app_config(join_url_parts(django_urls.prefix, route).lchop("/"), app_config_path, route_path).each do |endpoint|
              endpoints << endpoint
            end
            next
          end

          if imported_urlconf_path = extract_imported_include_target(view, package_map)
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
              extract_local_urlpattern_endpoints(django_urls, route, pattern_content, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations).each do |endpoint|
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
            endpoints << Endpoint.new(url, "GET", Details.new(route_path))
          else
            view = extract_wrapped_view_reference(view)
            if view_target = resolve_django_view_target(view, package_map)
              filepath, function_or_class_name = view_target
              extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
                append_code_path(endpoint.details, route_path)
                endpoints << endpoint
              end
            else
              # By default, Django allows requests with methods other than GET as well
              endpoints << Endpoint.new(url, "GET", Details.new(route_path))
            end
          end
        end
      end

      endpoints.concat(direct_router_endpoints)
      endpoints
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
      assign_capture_re = /^\s*(?:#{list_name_re})\s*=\s*(.+)$/m
      append_check_re = /^\s*(?:#{list_name_re})\s*\+=/
      append_capture_re = /^\s*(?:#{list_name_re})\s*\+=\s*(.+)$/m
      extend_check_re = /^\s*(?:#{list_name_re})\s*\.\s*extend\s*\(/
      extend_capture_re = /^\s*(?:#{list_name_re})\s*\.\s*extend\s*\((.*)\)\s*$/m

      lines.each_with_index do |line, index|
        if line.matches?(assign_check_re)
          logical_line = collect_python_expression(lines, index, line)
          if assignment_match = logical_line.match(assign_capture_re)
            add_urlpattern_expression_contents(contents, assignment_match[1], urlpattern_lists)
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

    private def split_python_expression_terms(expression : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_quote : Char? = nil
      escaped = false

      expression.each_char do |ch|
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
        when '+'
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

        pattern_lists[assignment_match[1]] = pieces.join("\n")
      end

      pattern_lists
    end

    private def extract_django_app_config_refs(content : ::String) : Hash(::String, ::String)
      refs = Hash(::String, ::String).new
      content.each_line do |line|
        next if line.lstrip.starts_with?("#")
        line.scan(/\bself\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*apps\.get_app_config\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
          next unless match.size == 3
          refs[match[1]] = match[2]
        end
      end
      refs
    end

    private def resolve_django_app_config_include_path(view : ::String,
                                                       app_config_refs : Hash(::String, ::String)) : ::String?
      if direct_match = view.match(/\bapps\.get_app_config\s*\(\s*['"]([^'"]+)['"]\s*\)\.urls\b/)
        return resolve_django_app_config_path(direct_match[1])
      end

      if self_match = view.match(/\bself\.([A-Za-z_][A-Za-z0-9_]*)\.urls\b/)
        ref_name = self_match[1]
        if label = app_config_refs[ref_name]?
          resolve_django_app_config_path(label)
        end
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
        next false if file.includes?("/site-packages/")
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
      expanded_key = "#{File.expand_path(app_config_path)}:#{prefix}"
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
                                                     parent_route_path : PathInfo) : Array(Endpoint)
      endpoints = [] of Endpoint

      extract_route_mappings(pattern_content).each do |route_mapping|
        route, view = route_mapping
        route = normalize_django_route(route)
        nested_prefix = join_url_parts(prefix, route).lchop("/")

        if nested_app_config_path = resolve_django_app_config_include_path(view, app_config_refs)
          extract_endpoints_from_django_app_config(nested_prefix, nested_app_config_path, route_path).each do |endpoint|
            append_code_path(endpoint.details, parent_route_path)
            endpoints << endpoint
          end
          next
        end

        if local_patterns = extract_local_include_target(view)
          if nested_pattern_content = urlpattern_lists[local_patterns]?
            extract_app_config_pattern_endpoints(nested_prefix, nested_pattern_content, current_app_config_path, package_map, urlpattern_lists, app_config_refs, route_path, parent_route_path).each do |endpoint|
              endpoints << endpoint
            end
            next
          end
        end

        if inline_patterns = extract_inline_include_patterns(view)
          extract_app_config_pattern_endpoints(nested_prefix, inline_patterns, current_app_config_path, package_map, urlpattern_lists, app_config_refs, route_path, parent_route_path).each do |endpoint|
            endpoints << endpoint
          end
          next
        end

        if imported_urlconf_path = extract_imported_include_target(view, package_map)
          new_django_urls = DjangoUrls.new(nested_prefix, imported_urlconf_path, @django_base_path)
          unless @visited_url_paths.has_key? new_django_urls.filepath
            extract_endpoints(new_django_urls).each do |endpoint|
              append_code_path(endpoint.details, route_path)
              append_code_path(endpoint.details, parent_route_path)
              endpoints << endpoint
            end
          end
          next
        end

        url = join_url_parts(prefix, route)
        if view.empty?
          endpoint = Endpoint.new(url, "GET", Details.new(route_path))
          append_code_path(endpoint.details, parent_route_path)
          endpoints << endpoint
        else
          view = extract_wrapped_view_reference(view)
          if view_target = resolve_django_view_target(view, package_map)
            filepath, function_or_class_name = view_target
            extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
              append_code_path(endpoint.details, route_path)
              append_code_path(endpoint.details, parent_route_path)
              endpoints << endpoint
            end
          else
            endpoint = Endpoint.new(url, "GET", Details.new(route_path))
            append_code_path(endpoint.details, parent_route_path)
            endpoints << endpoint
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

    private def python_bracket_delta(line : ::String) : Int32
      depth = 0
      in_quote : Char? = nil
      escaped = false

      line.each_char do |ch|
        if in_quote
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
        when '['
          depth += 1
        when ']'
          depth -= 1
        end
      end

      depth
    end

    private def extract_route_mappings(content : ::String) : Array(Tuple(::String, ::String))
      mappings = [] of Tuple(::String, ::String)
      lines = content.split("\n")
      inline_include_depth = 0

      lines.each_with_index do |line, index|
        if inline_include_depth > 0
          inline_include_depth += python_bracket_delta(line)
          inline_include_depth = 0 if inline_include_depth < 0
          next
        end

        next if line.lstrip.starts_with?("#")
        next unless line.matches?(/\b(?:url|path|re_path|register)\s*\(/)

        logical_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        call_match = logical_line.match(/\b(?:url|path|re_path|register)\s*\((.*)\)/m)
        next unless call_match

        args = split_python_arguments(call_match[1])
        next if args.size < 2

        route = extract_python_string(args[0])
        route ||= extract_python_keyword_string(args, "route")
        route ||= extract_python_keyword_string(args, "regex")
        next unless route

        view_expr = extract_python_keyword_expression(args, "view")
        view_expr ||= args[1]?.try do |candidate|
          if keyword_view = candidate.match(/^\s*view\s*=\s*(.+)$/m)
            keyword_view[1].strip
          else
            candidate.strip
          end
        end
        view_expr ||= ""
        mappings << {route, view_expr}

        if line.includes?("include([")
          include_start = line.index("include([") || 0
          inline_include_depth = python_bracket_delta(line[include_start..])
        end
      end

      mappings
    end

    private def normalize_django_route(route : ::String) : ::String
      normalized = route.gsub(/^\^/, "").gsub(/\$$/, "")
      normalize_django_named_regex_groups(normalized)
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
      lines = content.split("\n")

      lines.each_with_index do |line, index|
        next if line.lstrip.starts_with?("#")
        next unless line.includes?(".register(")

        logical_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        register_match = logical_line.match(/\b([A-Za-z_][A-Za-z0-9_]*)\.register\s*\((.*)\)/m)
        next unless register_match

        args = split_python_arguments(register_match[2])
        next if args.empty?

        prefix = extract_python_string(args[0]) || extract_python_keyword_string(args, "prefix")
        next unless prefix

        view_ref = extract_python_keyword_expression(args, "viewset") || args[1]?.try(&.strip)
        next unless view_ref
        view_ref = clean_python_reference(view_ref)
        next if view_ref.empty?

        registrations[register_match[1]] << DjangoDrfRegistration.new(prefix, view_ref)
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
      include_match = view.match(/\binclude\s*\(\s*(\[[\s\S]*\])\s*(?:,\s*namespace\s*=|\))?/m)
      include_match ? include_match[1] : nil
    end

    private def extract_imported_include_target(view : ::String, package_map) : ::String?
      include_match = view.match(/\binclude\s*\(\s*(?:\(\s*)?([A-Za-z_][A-Za-z0-9_]*)\b/)
      return unless include_match

      target_name = include_match[1]
      return if view.includes?("#{target_name}.urls")
      imported = package_map[target_name]?
      return unless imported

      filepath, package_type = imported
      return unless package_type == PackageType::FILE
      return unless File.exists?(filepath)

      filepath
    end

    private def extract_local_urlpattern_endpoints(django_urls : DjangoUrls,
                                                   mount_route : ::String,
                                                   pattern_content : ::String,
                                                   package_map,
                                                   route_path : PathInfo,
                                                   urlpattern_lists : Hash(::String, ::String),
                                                   import_aliases : Hash(::String, ::String),
                                                   drf_router_registrations : Hash(::String, Array(DjangoDrfRegistration))) : Array(Endpoint)
      endpoints = [] of Endpoint

      extract_route_mappings(pattern_content).each do |route_mapping|
        route, view = route_mapping
        route = normalize_django_route(route)
        nested_mount = join_url_parts(mount_route, route).lchop("/")

        if local_patterns = extract_local_include_target(view)
          if nested_pattern_content = urlpattern_lists[local_patterns]?
            extract_local_urlpattern_endpoints(django_urls, nested_mount, nested_pattern_content, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations).each do |endpoint|
              endpoints << endpoint
            end
            next
          end
        end

        if inline_patterns = extract_inline_include_patterns(view)
          extract_local_urlpattern_endpoints(django_urls, nested_mount, inline_patterns, package_map, route_path, urlpattern_lists, import_aliases, drf_router_registrations).each do |endpoint|
            endpoints << endpoint
          end
          next
        end

        if imported_urlconf_path = extract_imported_include_target(view, package_map)
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
          endpoints << Endpoint.new(url, "GET", Details.new(route_path))
          next
        end

        view = extract_wrapped_view_reference(view)
        resolved = resolve_django_view_reference(view, package_map)
        if resolved
          filepath, function_or_class_name = resolved
          if /^[a-zA-Z_][a-zA-Z0-9_]*$/.match(function_or_class_name)
            extract_endpoints_from_file(url, filepath, function_or_class_name).each do |endpoint|
              append_code_path(endpoint.details, route_path)
              endpoints << endpoint
            end
            next
          end
        end

        endpoints << Endpoint.new(url, "GET", Details.new(route_path))
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
      extract_drf_viewset_endpoints(route_base, filepath, class_name)
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

      view
    end

    private def extract_python_string(expression : ::String) : ::String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def extract_python_keyword_expression(args : Array(::String), keyword : ::String) : ::String?
      args.each do |arg|
        keyword_match = arg.match(/^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m)
        return keyword_match[1].strip if keyword_match
      end

      nil
    end

    private def extract_python_keyword_string(args : Array(::String), keyword : ::String) : ::String?
      if expression = extract_python_keyword_expression(args, keyword)
        return extract_python_string(expression)
      end

      nil
    end

    private def clean_python_reference(expression : ::String) : ::String
      reference = expression.strip
      reference = reference.split("#", 2)[0].strip
      return reference if reference.matches?(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/)

      ""
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_quote : Char? = nil
      escaped = false

      args.each_char do |ch|
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

    # Extract endpoints from a given file
    def extract_endpoints_from_file(url : ::String, filepath : ::String, function_or_class_name : ::String)
      @logger.debug "Extracting endpoints from #{filepath}"

      endpoints = Array(Endpoint).new
      suspicious_http_methods = ["GET"]
      suspicious_params = Array(Param).new

      content = read_file_content(filepath)
      content_lines = content.split "\n"

      # Function Based View
      function_start_index = content.index /(?:async\s+)?def\s+#{function_or_class_name}\s*\(/
      unless function_start_index.nil?
        function_codeblock = parse_code_block(content[function_start_index..])
        unless function_codeblock.nil?
          lines = function_codeblock.split "\n"
          function_define_line = lines[0]
          lines = lines[1..]

          # Check the decorator stack above the def for HTTP methods.
          # Walk every contiguous decorator line (not just the one
          # directly above the def) so a method-restricting decorator
          # under, say, `@login_required` is still seen.
          index = content_lines.index(function_define_line)
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
                HTTP_METHODS.each do |http_method_name|
                  method_name_match = preceding_definition.downcase.match /[^a-zA-Z0-9](#{http_method_name})[^a-zA-Z0-9]/
                  unless method_name_match.nil?
                    suspicious_http_methods << http_method_name.upcase
                  end
                end
              end
            end

            # A method-restricting decorator replaces the implicit GET.
            if rm = restricted_methods
              suspicious_http_methods = rm unless rm.empty?
            end
          end

          lines.each do |line|
            # Check if line has 'request.method == "GET"' similar pattern
            if line.includes? "request.method"
              suspicious_code = line.split("request.method")[1].strip
              HTTP_METHODS.each do |http_method_name|
                method_name_match = suspicious_code.downcase.match /['"](#{http_method_name})['"]/
                unless method_name_match.nil?
                  suspicious_http_methods << http_method_name.upcase
                end
              end
            end

            extract_params_from_line(line, suspicious_http_methods).each do |param|
              suspicious_params << param
            end
          end

          # Build once outside the per-method emit loop: a view function
          # routinely emits multiple endpoints (one per detected HTTP
          # method), but they all share the same handler body. The
          # codeblock starts at the `def` line, so `body_start_line` is
          # that line's 0-based index — derived from the char offset.
          body_start_line = content[0, function_start_index].count('\n')
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
            handler_callees.each { |c| endpoint.push_callee(c) }
            endpoints << endpoint
          end

          return endpoints
        end
      end

      # Class Based View
      class_start_index = content.index /class\s+#{function_or_class_name}\s*[\(:]/
      unless class_start_index.nil?
        class_codeblock = parse_python_class_codeblock(content, class_start_index) || parse_code_block(content[class_start_index..])
        unless class_codeblock.nil?
          lines = class_codeblock.split "\n"
          class_define_line = lines[0]
          lines = lines[1..]

          drf_generic_class = false
          if drf_methods = default_drf_generic_view_methods(class_define_line)
            drf_generic_class = true
            suspicious_http_methods = drf_methods
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

          body_start_line = content[0, class_start_index].count('\n')
          class_definition_line = body_start_line + 1
          method_callees = Hash(String, Array(Callee)).new
          method_lines = Hash(String, Int32).new
          common_params = Array(Param).new
          method_params = Hash(String, Array(Param)).new do |hash, key|
            hash[key] = [] of Param
          end
          current_http_methods : Array(String)? = nil

          # Check HTTP methods in class methods
          lines.each_with_index do |line, offset|
            method_function_match = line.match(REGEX_CBV_METHOD_DEF)
            any_method_function_match = line.match(/\s+(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/)
            unless any_method_function_match.nil?
              current_http_methods = nil
            end

            if !method_function_match.nil?
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
              extract_params_from_line(line, scan_methods).each do |param|
                method_names.each do |mapped_method_name|
                  next unless suspicious_http_methods.includes?(mapped_method_name)
                  method_params[mapped_method_name] << param
                end
              end
            else
              extract_params_from_line(line, suspicious_http_methods).each do |param|
                common_params << param
              end
            end
          end

          if suspicious_http_methods.empty?
            return endpoints
          end

          suspicious_http_methods.uniq.each do |http_method_name|
            definition_line = method_lines[http_method_name]? || class_definition_line
            details = Details.new(PathInfo.new(filepath, definition_line))
            endpoint_params = common_params + (method_params[http_method_name]? || [] of Param)
            endpoint = Endpoint.new(url, http_method_name, filter_params(http_method_name, endpoint_params), details)
            if callees = method_callees[http_method_name]?
              callees.each { |c| endpoint.push_callee(c) }
            end
            endpoints << endpoint
          end

          return endpoints
        end
      end

      # Default to GET method
      [Endpoint.new(url, "GET", Details.new(PathInfo.new(filepath)))]
    end

    private def default_drf_generic_view_methods(class_define_line : ::String) : Array(::String)?
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

    private def extract_drf_viewset_endpoints(route_base : ::String, filepath : ::String, class_name : ::String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(filepath)
      class_start_index = content.index /class\s+#{class_name}\s*[\(:]/
      return endpoints unless class_start_index

      class_codeblock = parse_python_class_codeblock(content, class_start_index) || parse_code_block(content[class_start_index..])
      return endpoints unless class_codeblock

      lines = class_codeblock.split("\n")
      class_define_line = extract_python_definition_header(lines)
      body_lines = lines[1..]
      body_start_line = content[0, class_start_index].count('\n')
      class_definition_line = body_start_line + 1
      lookup_param = extract_drf_lookup_param(class_codeblock)
      actions = default_drf_viewset_actions(class_define_line)

      body_lines.each_with_index do |line, offset|
        method_match = line.match(/\s+(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/)
        next unless method_match

        action_name = method_match[1]
        method_actions = [] of DjangoDrfAction
        if action = drf_action_for_method(action_name)
          method_actions << action
        else
          method_actions = extract_drf_action_decorators(body_lines, offset, action_name)
        end
        next if method_actions.empty?

        codeblock = parse_code_block(body_lines[offset..])
        method_actions.each do |drf_action|
          drf_action.definition_line = body_start_line + offset + 2
          if codeblock
            codeblock.split("\n").each do |body_line|
              extract_params_from_line(body_line, [drf_action.method]).each do |param|
                drf_action.params << param
              end
            end
            drf_action.callees = build_callees_from(
              codeblock,
              body_start_line + offset + 1,
              filepath,
              definition_base_path: @django_base_path,
              source: content
            )
          end

          actions.reject! { |existing| existing.name == drf_action.name && existing.method == drf_action.method && existing.detail == drf_action.detail }
          actions << drf_action
        end
      end

      actions.each do |action|
        endpoint_path = drf_action_path(route_base, lookup_param, action)
        params = filter_params(action.method, action.params)
        params << Param.new(lookup_param, "", "path") if action.detail
        params = dedupe_params(params)
        details = Details.new(PathInfo.new(filepath, action.definition_line || class_definition_line))
        endpoint = Endpoint.new(endpoint_path, action.method, params, details)
        action.callees.each { |callee| endpoint.push_callee(callee) }
        endpoints << endpoint
      end

      endpoints
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

    private def extract_drf_action_decorators(lines : Array(::String), method_line_index : Int32, method_name : ::String) : Array(DjangoDrfAction)
      index = method_line_index - 1
      while index >= 0
        stripped = lines[index].strip
        break if stripped.empty? || stripped.starts_with?("def ") || stripped.starts_with?("class ")

        if stripped.starts_with?("@action") || stripped == ")" || stripped.includes?("url_path") || stripped.includes?("methods") || stripped.includes?("detail")
          decorator_source = collect_preceding_decorator_source(lines, index)
          # A bare `next` here would skip the trailing `index -= 1`, spinning the
          # `while` forever on guard matches that lack an @action decorator.
          unless decorator_source.includes?("@action")
            index -= 1
            next
          end

          args_match = decorator_source.match(/@action\s*\((.*?)\)/m)
          args = args_match ? args_match[1] : ""
          detail = args.matches?(/\bdetail\s*=\s*True\b/)
          methods = extract_drf_action_methods(args)
          url_path = extract_drf_action_url_path(args) || method_name.gsub("_", "-")
          return methods.map { |method| DjangoDrfAction.new(method_name, method, detail, url_path) }
        end

        index -= 1
      end

      [] of DjangoDrfAction
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

    private def collect_preceding_decorator_source(lines : Array(::String), index : Int32) : ::String
      start_index = index
      while start_index > 0
        previous = lines[start_index - 1].strip
        break if previous.empty? || previous.matches?(/^(?:async\s+)?def\s+/) || previous.starts_with?("class ")
        start_index -= 1
        break if previous.starts_with?("@")
      end

      lines[start_index..index].join("\n")
    end

    private def parse_python_class_codeblock(content : ::String, class_start_index : Int32) : ::String?
      lines = content[class_start_index..].split("\n")
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

    private def extract_drf_lookup_param(class_codeblock : ::String) : ::String
      if lookup_url_kwarg = class_codeblock.match(/\blookup_url_kwarg\s*=\s*[rf]?['"]([^'"]+)['"]/)
        return lookup_url_kwarg[1]
      end

      if lookup_field = class_codeblock.match(/\blookup_field\s*=\s*[rf]?['"]([^'"]+)['"]/)
        return lookup_field[1]
      end

      "pk"
    end

    private def drf_action_path(route_base : ::String, lookup_param : ::String, action : DjangoDrfAction) : ::String
      parts = [route_base]
      parts << "{#{lookup_param}}" if action.detail
      parts << action.path unless action.path.empty?
      ensure_trailing_slash(join_url_parts(parts))
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

      nil
    end

    # Extract parameters from a line of code
    def extract_params_from_line(line : ::String, endpoint_methods : Array(::String))
      suspicious_params = Array(Param).new

      if line.includes? "request."
        REQUEST_PARAM_FIELD_PATTERNS.each do |field_pattern|
          field_name, field_methods, param_type, bracket_re, get_re = field_pattern
          matches = line.scan(bracket_re)
          if matches.size == 0
            matches = line.scan(get_re)
          end

          if matches.size != 0
            matches.each do |match|
              next if match.size != 2
              param_name = match[1]
              if field_name == "META"
                if param_name.starts_with? "HTTP_"
                  param_name = param_name[5..]
                end
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
        if matches.size == 0
          matches = line.scan(/form\.cleaned_data\.get\([rf]?['"]([^'"]*)['"]/)
        end

        if matches.size != 0
          matches.each do |match|
            next if match.size != 2
            suspicious_params << Param.new(match[1], "", "form")
          end
        end
      end

      suspicious_params
    end

    # Filter parameters based on HTTP method
    def filter_params(method : ::String, params : Array(Param))
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_supported_param = false
        support_methods = REQUEST_PARAM_TYPE_MAP.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            if upper_method == support_method.upcase
              is_supported_param = true
            end
          end
        else
          is_supported_param = true
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
      property prefix, view_ref

      def initialize(@prefix : ::String, @view_ref : ::String)
      end
    end

    class DjangoDrfAction
      property name, method, detail, path, params, definition_line, callees

      @definition_line : Int32?

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
