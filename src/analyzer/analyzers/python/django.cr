require "../../engines/python_engine"
require "json"

module Analyzer::Python
  class Django < PythonEngine
    # Base path for the Django project
    @django_base_path : ::String = ""
    @visited_url_paths = Hash(String, Bool).new

    # Regular expressions for extracting Django URL configurations
    REGEX_ROOT_URLCONF  = /\s*ROOT_URLCONF\s*=\s*r?['"]([^'"\\]*)['"]/
    REGEX_ROUTE_MAPPING = /\b(?:url|path|re_path|register)\s*\(\s*r?['"]([^"']*)['"][^,]*,\s*([^),]*)/
    REGEX_INCLUDE_URLS  = /\binclude\s*\(\s*r?['"]([^'"\\]*)['"]/

    # Map request parameters to their respective fields
    REQUEST_PARAM_FIELD_MAP = {
      "GET"          => {["GET"], "query"},
      "POST"         => {["POST"], "form"},
      "COOKIES"      => {nil, "cookie"},
      "META"         => {nil, "header"},
      "data"         => {["POST", "PUT", "PATCH"], "form"},
      "query_params" => {nil, "query"},
    }

    # Map request parameter types to HTTP methods
    REQUEST_PARAM_TYPE_MAP = {
      "query"  => nil,
      "form"   => ["GET", "POST", "PUT", "PATCH"],
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

      # Find static files
      begin
        static_prefix = "#{@base_path}/static/"
        get_files_by_prefix(static_prefix).each do |file|
          relative_path = file.sub("#{@base_path}/static/", "")
          endpoints << Endpoint.new("/#{relative_path}", "GET")
        end
      rescue e
        logger.debug e
      end

      endpoints
    end

    # Find all root Django URLs
    def find_root_django_urls : Array(DjangoUrls)
      root_django_urls_list = [] of DjangoUrls
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      search_dir = @base_path

      populate_channel_with_files(channel)

      WaitGroup.wait do |wg|
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
                next if PythonEngine.python_test_path?(file)
                if file.ends_with? ".py"
                  content = read_file_content(file)
                  content.scan(REGEX_ROOT_URLCONF) do |match|
                    next if match.size != 2
                    dotted_as_urlconf = match[1].split(".")
                    relative_path = "#{dotted_as_urlconf.join("/")}.py"

                    Dir.glob("#{escape_glob_path(search_dir)}/**/#{relative_path}") do |filepath|
                      basepath = filepath.split("/")[..-(dotted_as_urlconf.size + 1)].join("/")
                      root_django_urls_list << DjangoUrls.new("", filepath, basepath)
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
            dotted_as_names_split = view.split(".")

            filepath = ""
            function_or_class_name = ""
            dotted_as_names_split.each_with_index do |name, index|
              if (package_map.has_key? name) && (index < dotted_as_names_split.size)
                filepath, package_type = package_map[name]
                function_or_class_name = name
                if package_type == PackageType::FILE && index + 1 < dotted_as_names_split.size
                  function_or_class_name = dotted_as_names_split[index + 1]
                end

                break
              end
            end

            if !filepath.empty? && /^[a-zA-Z_][a-zA-Z0-9_]*$/.match(function_or_class_name)
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
      contents = [] of ::String
      lines = content.split("\n")

      lines.each_with_index do |line, index|
        if line.matches?(/^\s*urlpatterns\s*=/)
          logical_line = collect_python_expression(lines, index, line)
          if assignment_match = logical_line.match(/^\s*urlpatterns\s*=\s*(.+)$/m)
            add_urlpattern_expression_contents(contents, assignment_match[1], urlpattern_lists)
          end
        elsif line.matches?(/^\s*urlpatterns\s*\+=/)
          logical_line = collect_python_expression(lines, index, line)
          if append_match = logical_line.match(/^\s*urlpatterns\s*\+=\s*(.+)$/m)
            add_urlpattern_expression_contents(contents, append_match[1], urlpattern_lists)
          end
        elsif line.matches?(/^\s*urlpatterns\s*\.\s*extend\s*\(/)
          logical_line = collect_python_expression(lines, index, line)
          if extend_match = logical_line.match(/^\s*urlpatterns\s*\.\s*extend\s*\((.*)\)\s*$/m)
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

      lines.each_with_index do |line, index|
        next unless line.matches?(/\b(?:url|path|re_path|register)\s*\(/)

        logical_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        call_match = logical_line.match(/\b(?:url|path|re_path|register)\s*\((.*)\)/m)
        next unless call_match

        args = split_python_arguments(call_match[1])
        next if args.size < 2

        route = extract_python_string(args[0])
        next unless route

        mappings << {route, args[1].strip}
      end

      mappings
    end

    private def normalize_django_route(route : ::String) : ::String
      normalized = route.gsub(/^\^/, "").gsub(/\$$/, "")
      normalized.gsub(/\(\?P<([A-Za-z_][A-Za-z0-9_]*)>[^)]*\)/) do
        "{#{$~[1]}}"
      end
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

      content.scan(/\burlpatterns\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      content.scan(/\burlpatterns\s*\+=\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      content.scan(/\burlpatterns\b[^\n]*\+\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\b/) do |match|
        router_names << match[1] if match.size == 2
      end

      content.scan(/\burlpatterns\s*\.\s*extend\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\.urls\s*\)/) do |match|
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
      function_start_index = content.index /def\s+#{function_or_class_name}\s*\(/
      if !function_start_index.nil?
        function_codeblock = parse_code_block(content[function_start_index..])
        if !function_codeblock.nil?
          lines = function_codeblock.split "\n"
          function_define_line = lines[0]
          lines = lines[1..]

          # Check if the decorator line contains an HTTP method
          index = content_lines.index(function_define_line)
          if !index.nil?
            while index > 0
              index -= 1

              preceding_definition = content_lines[index]
              if preceding_definition.size > 0 && preceding_definition[0] == '@'
                HTTP_METHODS.each do |http_method_name|
                  method_name_match = preceding_definition.downcase.match /[^a-zA-Z0-9](#{http_method_name})[^a-zA-Z0-9]/
                  if !method_name_match.nil?
                    suspicious_http_methods << http_method_name.upcase
                  end
                end
              end

              break
            end
          end

          lines.each do |line|
            # Check if line has 'request.method == "GET"' similar pattern
            if line.includes? "request.method"
              suspicious_code = line.split("request.method")[1].strip
              HTTP_METHODS.each do |http_method_name|
                method_name_match = suspicious_code.downcase.match /['"](#{http_method_name})['"]/
                if !method_name_match.nil?
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
      regext_http_methods = HTTP_METHODS.join "|"
      class_start_index = content.index /class\s+#{function_or_class_name}\s*[\(:]/
      if !class_start_index.nil?
        class_codeblock = parse_python_class_codeblock(content, class_start_index) || parse_code_block(content[class_start_index..])
        if !class_codeblock.nil?
          lines = class_codeblock.split "\n"
          class_define_line = lines[0]
          lines = lines[1..]

          # Determine implicit HTTP methods based on class name
          if class_define_line.includes? "Form"
            suspicious_http_methods << "GET"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Delete"
            suspicious_http_methods << "DELETE"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Create"
            suspicious_http_methods << "POST"
          elsif class_define_line.includes? "Update"
            suspicious_http_methods << "POST"
          end

          body_start_line = content[0, class_start_index].count('\n')
          class_definition_line = body_start_line + 1
          method_callees = Hash(String, Array(Callee)).new
          method_lines = Hash(String, Int32).new
          common_params = Array(Param).new
          method_params = Hash(String, Array(Param)).new do |hash, key|
            hash[key] = [] of Param
          end
          current_http_method : String? = nil

          # Check HTTP methods in class methods
          lines.each_with_index do |line, offset|
            method_function_match = line.match(/\s+(?:async\s+)?def\s+(#{regext_http_methods})\s*\(/)
            any_method_function_match = line.match(/\s+(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/)
            if !any_method_function_match.nil?
              current_http_method = nil
            end

            if !method_function_match.nil?
              method_name = method_function_match[1].upcase
              current_http_method = method_name
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
            end

            extract_params_from_line(line, suspicious_http_methods).each do |param|
              if method_name = current_http_method
                method_params[method_name] << param
              else
                common_params << param
              end
            end
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
        endpoints << Endpoint.new(endpoint_path, action.method, params, details)
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
          next unless decorator_source.includes?("@action")

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

    # Extract parameters from a line of code
    def extract_params_from_line(line : ::String, endpoint_methods : Array(::String))
      suspicious_params = Array(Param).new

      if line.includes? "request."
        REQUEST_PARAM_FIELD_MAP.each do |field_name, tuple|
          field_methods, param_type = tuple
          matches = line.scan(/request\.#{field_name}\[[rf]?['"]([^'"]*)['"]\]/)
          if matches.size == 0
            matches = line.scan(/request\.#{field_name}\.get\([rf]?['"]([^'"]*)['"]/)
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
              if !field_methods.nil?
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
      property name, method, detail, path, params, definition_line

      @definition_line : Int32?

      def initialize(@name : ::String,
                     @method : ::String,
                     @detail : Bool,
                     @path : ::String,
                     @params = [] of Param,
                     @definition_line = nil)
      end
    end
  end
end
