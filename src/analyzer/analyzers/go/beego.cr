require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Beego < GoEngine
    IMPORT_MARKER = "github.com/beego/beego"

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile), and this fixed accessor set used to be
    # rebuilt for every line — precompile it once at load time.
    CONTEXT_GETTER_PATTERNS = ["GetString", "GetStrings", "GetInt", "GetInt8", "GetUint8", "GetInt16", "GetUint16", "GetInt32", "GetUint32",
                               "GetInt64", "GetUint64", "GetBool", "GetFloat"].map do |pattern|
      {pattern, /#{pattern}\("([^"]*)"\)/}
    end

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Beego's
      # `web.Get("/x", h)` shape is picked up by `extract_routes`, and
      # callee resolution wires identical to Gin/Echo/etc. Beego doesn't
      # use group routes, so we just need file_contents — no fixpoint.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      # Per-directory controller-method map so mapping-less
      # `web.Router("/x", &Ctrl{})` registrations resolve to the exact
      # HTTP methods the controller implements.
      package_controller_methods = collect_package_controller_methods(file_contents)
      # Per-directory controller-method bodies, so a `web.Router` route's
      # handler (a controller method named in the mapping string) gets its
      # 1-hop callees walked even though the call doesn't pass it as an
      # argument. Empty unless callees are requested.
      package_controller_method_bodies = collect_package_controller_method_bodies(file_contents)
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

                    # Functional `web.Get("/x", h)` verb routes plus
                    # controller-style `web.Router("/x", &Ctrl{}, "get:M")`
                    # registrations — the latter is Beego's dominant idiom.
                    controller_methods = ts_controller_methods_for_directory(package_controller_methods, File.dirname(path))
                    beego_routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(content, controller_methods)
                    # Track which lines are `web.Router` registrations so the
                    # controller-method callee fallback below only fires for
                    # them — never for a `web.Get` verb route whose handler
                    # text happens to collide with a method name.
                    beego_router_lines = Set(Int32).new
                    beego_routes.each { |r| beego_router_lines << r.line }
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content) + beego_routes
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
                    controller_method_bodies = ts_controller_method_bodies_for_directory(package_controller_method_bodies, File.dirname(path))

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
                            if entries = callees_by_route[route.line]?
                              entries.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            elsif callees_needed? && beego_router_lines.includes?(route.line) &&
                                  !route.handler.empty? &&
                                  (bodies = controller_method_bodies[route.handler]?) && bodies.size == 1
                              # `web.Router` routes carry the controller
                              # method name in `handler`; the registration
                              # call doesn't pass it as an argument, so walk
                              # the method body here. Only when exactly one
                              # controller in the package defines the name
                              # (avoids mis-attributing an ambiguous method).
                              Noir::GoCalleeExtractor.callees_in_body(bodies.first, external_fns).each do |name, callee_path, callee_line|
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      CONTEXT_GETTER_PATTERNS.each do |pattern, getter_regex|
                        # Quote-bounded + scan so two accessor calls on one line
                        # each yield their own param (greedy `(.*)` captured across
                        # both, producing one garbage name).
                        next unless line.includes?(pattern)
                        line.scan(getter_regex) do |m|
                          last_endpoint.params << Param.new(m[1], "", "query")
                        end
                      end

                      if line.includes?("GetCookie(")
                        match = line.match(/GetCookie\(\"([^"]*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
                      end

                      if line.includes?("GetSecureCookie(")
                        match = line.match(/GetSecureCookie\(\"([^"]*)\"\)/)
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

      resolve_public_dirs_with_glob(public_dirs)

      result
    end
  end
end
