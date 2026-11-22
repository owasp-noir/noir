require "../../../models/analyzer"
require "../../../miniparsers/go_callee_extractor"
require "../../../miniparsers/go_route_extractor_ts"
require "../../../miniparsers/go_named_handler"
require "../../engines/go_engine"

module Analyzer::Go
  class Fasthttp < Analyzer
    include GoTestPath
    include GoRouteDetails
    analyzer_for "go_fasthttp"

    IMPORT_MARKER = "github.com/valyala/fasthttp"

    # One precompiled matcher instead of a `String#includes?` scan per
    # `.go` file: `includes?` runs Rabin-Karp over the whole buffer and
    # the marker is absent in the overwhelming majority of files in a
    # polyglot repo, so every one of them pays the full scan. See
    # `Analyzer#content_matches?`.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)

    def analyze
      # Source Analysis
      begin
        # Pulls from the detector-built file_map so subtree pruning and
        # --exclude-path apply to this pass too.
        go_files = get_files_by_extension(".go")

        # Pre-pass for cross-file identifier-handler resolution.
        # Fasthttp extends `Analyzer` directly (not `GoEngine`), so we
        # build the file_contents hash inline and use the module-level
        # twins on `GoCalleeExtractor`.
        file_contents = Hash(String, String).new
        go_files.each do |fp|
          next if go_test_path?(fp)
          begin
            file_contents[fp] = read_file_content(fp)
          rescue IO::Error
            # skip
          end
        end
        package_function_bodies = Noir::GoCalleeExtractor.lazy_package_bodies_if(callees_needed?, file_contents)
        # Resolve method-value handlers (`h.Index`) to their bodies too,
        # so callees aren't empty when handlers hang off a struct.
        package_method_bodies = Noir::GoCalleeExtractor.lazy_package_bodies_if(callees_needed?, file_contents)

        named_scope = Noir::GoNamedHandler.scope(file_contents)

        base_paths.each do |current_base_path|
          go_files.each do |path|
            next unless path_under_root?(path, current_base_path)
            next if go_test_path?(path)
            if File.exists?(path)
              content = read_file_content(path)
              next unless content_matches?(content, IMPORT_MARKER_RE)
              last_endpoint = Endpoint.new("", "")

              # Tree-sitter pre-pass: fasthttp has no groups, so we just
              # pull every `<router>.<VERB>("/path", ...)` the extractor
              # finds. The extra string constraint (`"/..."`) the legacy
              # regex enforced is already covered — `decode_verb_call`
              # returns nil when the first string arg is empty.
              ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content)
              routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
              ts_routes.each do |r|
                # Fasthttp accepts paths starting with `/`; drop anything
                # else (the legacy regex had the same constraint).
                next unless r.raw_path.starts_with?("/")
                routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                routes_by_line[r.line] << r
              end

              # Resolve 1-hop callees for every route (see Gin).
              route_rows = Set(Int32).new
              routes_by_line.each_key { |row| route_rows << row }
              external_fns = Noir::GoCalleeExtractor.function_bodies_for_directory(package_function_bodies, File.dirname(path))
              external_methods = Noir::GoCalleeExtractor.method_bodies_for_directory(package_method_bodies, File.dirname(path))
              callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)
              named = go_named_handler(content, path, ts_routes, named_scope)

              GoEngine.strip_comments(content).each_line.with_index do |line, index|
                next if named.claim?(index, line)

                if ts_hits = routes_by_line[index]?
                  ts_hits.each do |route|
                    details = go_route_details(route, path, content)
                    clean_path = Noir::URLPath.normalize(route.path, Noir::URLPath::BRACE_OPTIONAL_CONSTRAINT, rooted: false)
                    Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                      endpoint = Endpoint.new(clean_path, verb, details)
                      if entries = callees_by_route[route.line]?
                        entries.each do |entry|
                          name, callee_path, callee_line = entry
                          endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                        end
                      end
                      endpoint.handler = named.handler_for(route)
                      endpoint.resolution = named.resolution_for(route)
                      result << endpoint
                      named.bind(route, endpoint)
                      last_endpoint = endpoint
                    end
                  end
                end

                add_fasthttp_params(line, last_endpoint)
              end

              named.each_attribution { |line, ep| add_fasthttp_params(line, ep) }
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    SIMPLE_ROUTER_PATH = /\A(?:[\/\w.~-]|\{\w+\})*\z/

    private def add_fasthttp_params(line : String, endpoint : Endpoint)
      return if endpoint.method.empty?
      analyze_param_line(line).each do |param|
        next if param.name.empty?
        # UserValue is a context lookup. On a fully resolved literal path
        # with ordinary brace captures, only a matching capture is a path input.
        if param.param_type == "path" && endpoint.handler && endpoint.resolution.nil? &&
           endpoint.url.matches?(SIMPLE_ROUTER_PATH) && !endpoint.url.includes?("{#{param.name}}")
          next
        end
        unless endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
          endpoint.params << param
        end
      end
    end

    # Cheap pre-filter for `analyze_param_line`, called on EVERY line of
    # every fasthttp file (not just route lines). A precompiled union skips
    # all accessor scans on lines without any of their required substrings.
    PARAM_LINE_SIGNAL_RE = Regex.union(
      "QueryArgs", "PostArgs", "Request.Header", "FormValue", "UserValue",
      "PostBody", ".Request.Body(",
    )

    private def analyze_param_line(line : String) : Array(Param)
      params = [] of Param
      return params unless line.matches?(PARAM_LINE_SIGNAL_RE)

      # QueryArgs().Peek("param") or PostArgs().Peek("param")
      line.scan(/\b(QueryArgs|PostArgs)\(\)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_type = match[1] == "QueryArgs" ? "query" : "form"
        params << Param.new(match[2], "", param_type)
      end

      # Request.Header.Peek("header")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "header")
      end

      # Cookie access: ctx.Request.Header.Cookie("name")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.Cookie\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "cookie")
      end

      # Form values: ctx.FormValue("param")
      line.scan(/ctx\.FormValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "form")
      end

      # UserValue for path parameters: ctx.UserValue("param")
      line.scan(/ctx\.UserValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end

      # Body access: fasthttp exposes the raw body via `ctx.PostBody()`
      # or `ctx.Request.Body()`. A handler that reads either is consuming
      # a request body — surface a single body indicator (the body is
      # usually subsequently passed to json.Unmarshal which we can't
      # always pin to a specific field set).
      if line.includes?("ctx.PostBody(") || line.includes?(".Request.Body(") ||
         line.matches?(/json\.Unmarshal\([^)]*\.PostBody\(\)/)
        params << Param.new("body", "", "json")
      end

      params
    end
  end
end
