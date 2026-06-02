require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Gf < GoEngine
    IMPORT_MARKER = "github.com/gogf/gf"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Gf
      # doesn't use the route extractor's cross-file group fixpoint
      # (its closure-scoped walker handles groups directly), so we
      # build the file_contents hash via a dedicated helper.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
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
                  if File.exists?(path)
                    content = read_file_content(path)
                    next unless content.includes?(IMPORT_MARKER)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # GoFrame standardized routing: request structs embed
                    # `g.Meta` with `path:`/`method:` tags that fully
                    # define the route. These live in dedicated API
                    # definition files (no verb-call registration), so
                    # they're emitted directly here rather than through
                    # the closure-scoped walker. Gated on the `g.Meta`
                    # marker so files without it skip the tree-sitter
                    # parse entirely.
                    if content.includes?("g.Meta") && content.includes?("path:")
                      Noir::TreeSitterGoRouteExtractor.extract_gf_meta_routes(content).each do |mr|
                        mr_details = Details.new(PathInfo.new(path, mr.line + 1))
                        # A `method:"all"`/method-less route (verb "ALL")
                        # responds to every HTTP method; fan it out the
                        # same way Gin's `r.Any` is, so it isn't dropped by
                        # the optimizer's allowed-method filter.
                        verbs = mr.methods.flat_map { |m| Noir::TreeSitterGoRouteExtractor.fan_out_verbs(m) }.uniq!
                        verbs.each do |verb|
                          meta_ep = Endpoint.new(mr.path, verb, mr_details)
                          ptype = (verb == "GET" || verb == "HEAD" || verb == "DELETE") ? "query" : "json"
                          mr.params.each do |pname|
                            param = Param.new(pname, "", ptype)
                            meta_ep.params << param unless meta_ep.params.includes?(param)
                          end
                          result << meta_ep
                        end
                      end
                    end

                    # Tree-sitter pre-pass covers gf's three route shapes
                    # in one walk: closure groups `.Group("/x", func(){...})`,
                    # chained `s.Group("/multi").GET(...)`, and
                    # `.BindHandler("/x", h)` method-agnostic registrations.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_gf_routes(content)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          # BindHandler/BindMiddleware accept any method;
                          # fixtures expect GET, so fold "ALL" down.
                          verb = route.verb == "ALL" ? "GET" : route.verb
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

                      ["Get", "GetQuery", "GetForm", "GetHeader", "GetUploadFile"].each do |pattern|
                        if line.includes?("#{pattern}(") && !line.includes?("Cookie.Get")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Cookie.Get(")
                        match = line.match(/Cookie\.Get\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      resolve_public_dirs(public_dirs)

      result
    end

    def get_param(line : String) : Param
      param_type =
        if line.includes?("GetQuery(")
          "query"
        elsif line.includes?("GetForm(") || line.includes?("GetUploadFile(")
          "form"
        elsif line.includes?("GetHeader(")
          "header"
        else
          "json"
        end

      match = line.match(/\(\s*"([^"]+)"\s*\)/)
      if match
        return Param.new(match[1], "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
