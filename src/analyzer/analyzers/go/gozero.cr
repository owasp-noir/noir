require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class GoZero < GoEngine
    IMPORT_MARKER = "github.com/zeromicro/go-zero"

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The accessor set is fixed, so precompile
    # the per-accessor matchers once at load time.
    PARAM_ACCESSOR_PATTERNS = ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].to_h do |pattern|
      {pattern, /#{Regex.escape(pattern)}\(\s*"([^"]+)"/}
    end

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Only
      # `.go` routes (`server.Get("/x", h)` shape) get callees —
      # gozero's `.api` files are a non-Go DSL that declares routes as
      # `get /path (Request)` with an `@handler Name` directive; there's
      # no Go call_expression to extract a 1-hop graph from.
      # `read_package_file_contents` already filters to `.go`, so the
      # function-body map naturally skips `.api`.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            [".go", ".api"].each do |ext|
              get_files_by_extension(ext).each { |file| channel.send(file) }
            end
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)

                  # Handle both .go files and .api files
                  if File.exists?(path) && (File.extname(path) == ".go" || File.extname(path) == ".api")
                    content = read_file_content(path)
                    # `.api` files are gozero's DSL (no Go imports);
                    # only gate `.go` files on the import marker.
                    next if File.extname(path) == ".go" && !content.includes?(IMPORT_MARKER)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Go files: tree-sitter pre-pass (same verb-on-identifier
                    # pattern Gin uses, no groups in gozero's common idioms).
                    # .api files use a non-Go DSL — keep the legacy regex.
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    callees_by_route = Hash(Int32, Array(Tuple(String, String, Int32))).new
                    if File.extname(path) == ".go"
                      Noir::TreeSitterGoRouteExtractor.extract_routes(content).each do |r|
                        next unless r.raw_path.starts_with?("/")
                        routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                        routes_by_line[r.line] << r
                      end
                      Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                        public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
                      end

                      # Resolve 1-hop callees for every verb-style .go
                      # route. (Done before AddRoutes routes are folded in
                      # below: their handlers are cross-package wrapper
                      # refs, so directory-scoped body resolution can't
                      # reach them — they carry no 1-hop callees.)
                      route_rows = Set(Int32).new
                      routes_by_line.each_key { |row| route_rows << row }
                      external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                      callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                      # go-zero's canonical generated `routes.go`:
                      # `server.AddRoutes([]rest.Route{ {Method, Path,
                      # Handler}, ... }, rest.WithPrefix("/p"))`. These are
                      # struct literals, not verb calls, so the generic
                      # extractor misses them. Fold them into the same
                      # per-line map for emission with full mounted paths.
                      Noir::TreeSitterGoRouteExtractor.extract_gozero_routes(content).each do |r|
                        routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                        routes_by_line[r.line] << r
                      end
                    end

                    # `.api` route paths are relative to the `@server`
                    # block's `prefix:` (and go-zero mounts them under
                    # it). Track the active prefix as we scan so each
                    # `post /user/login` resolves to its full mounted
                    # path (`/usercenter/v1/user/login`) — matching what
                    # the generated `routes.go` registers via
                    # `rest.WithPrefix(...)`, so the two representations
                    # dedupe instead of producing half-paths.
                    api_prefix = ""
                    in_server_block = false

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Handle .api files (go-zero API definition files)
                      if File.extname(path) == ".api"
                        stripped = line.strip
                        if stripped.starts_with?("@server")
                          in_server_block = true
                          api_prefix = ""
                        elsif in_server_block && (pm = stripped.match(/^prefix:\s*"?([^"\s]+)"?/))
                          pfx = pm[1].strip
                          api_prefix = if pfx.empty?
                                         ""
                                       else
                                         pfx.starts_with?("/") ? pfx : "/#{pfx}"
                                       end
                        elsif in_server_block && stripped.starts_with?(")")
                          in_server_block = false
                        end

                        if match = line.match(/^\s*(get|post|put|delete|patch|head|options)\s+([^\s\(]+)/)
                          method = match[1].upcase
                          route_path = match[2]
                          full_path = if api_prefix.empty?
                                        route_path
                                      else
                                        rel = route_path.starts_with?("/") ? route_path : "/#{route_path}"
                                        "#{api_prefix}#{rel}"
                                      end
                          new_endpoint = Endpoint.new(full_path, method, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      # Handle .go files
                      if File.extname(path) == ".go"
                        if ts_hits = routes_by_line[index]?
                          ts_hits.each do |route|
                            Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                              new_endpoint = Endpoint.new(route.path, verb, details)
                              if entries = callees_by_route[route.line]?
                                entries.each do |entry|
                                  name, callee_path, callee_line = entry
                                  new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                                end
                              end
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        end

                        ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].each do |pattern|
                          if line.includes?("#{pattern}(")
                            add_param_to_endpoint(get_param(line, pattern), last_endpoint)
                          end
                        end

                        # gozero's canonical body-binding entrypoint is
                        # `httpx.Parse(r, &req)` / `httpx.ParseJsonBody`;
                        # both populate the request body. `json.NewDecoder`
                        # is also common in raw handlers.
                        if line.includes?("httpx.Parse(") || line.includes?("httpx.ParseJsonBody(") ||
                           line.includes?("httpx.ParseForm(") || line.matches?(/json\.NewDecoder\(.+\.Body\)/)
                          add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
                        end
                      end
                    end
                  end
                rescue
                  # Skip problematic files
                  next
                end
              end
            end
          end
        end
      rescue
        # Handle channel errors
      end

      resolve_public_dirs_with_glob(public_dirs)

      result
    end

    # Type the param by the actual accessor name. The previous
    # version always returned `"query"` regardless of accessor, so
    # `r.PathParam("id")` and `r.GetHeader("X-Token")` surfaced as
    # query params — a mis-classification that broke downstream
    # consumers (auth taggers, OpenAPI export) that key off
    # `param_type`.
    def get_param(line : String, pattern : String) : Param
      param_type = case pattern
                   when "Query"     then "query"
                   when "PostForm"  then "form"
                   when "FormValue" then "form"
                   when "GetHeader" then "header"
                   when "PathParam" then "path"
                   else                  "query"
                   end

      accessor_regex = PARAM_ACCESSOR_PATTERNS[pattern]? || /#{Regex.escape(pattern)}\(\s*"([^"]+)"/
      if match = line.match(accessor_regex)
        return Param.new(match[1], "", param_type)
      end
      Param.new("", "", "")
    end
  end
end
