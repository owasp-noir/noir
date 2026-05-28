require "../../../models/analyzer"
require "../../../miniparsers/go_callee_extractor"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Httprouter < Analyzer
    IMPORT_MARKER = "github.com/julienschmidt/httprouter"

    PARAM_PATTERNS = [
      {"ByName(", /ByName\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "path"},
      {"Query().Get(", /Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query"},
      {"PostFormValue(", /PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "form"},
      {"Header.Get(", /Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "header"},
      {"Cookie(", /Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "cookie"},
    ]

    def analyze
      # Source Analysis
      # Pre-pass for cross-file identifier-handler resolution.
      # Httprouter extends `Analyzer` directly (not `GoEngine`), so we
      # build the file_contents hash inline and use the module-level
      # twins on `GoCalleeExtractor`.
      file_contents = Hash(String, String).new
      get_files_by_extension(".go").each do |fp|
        next if File.directory?(fp)
        begin
          file_contents[fp] = read_file_content(fp)
        rescue File::NotFoundError
          # skip
        end
      end
      package_function_bodies = Noir::GoCalleeExtractor.package_function_bodies_if(callees_needed?, file_contents)

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

                    # Tree-sitter pre-pass: httprouter exposes HTTP verbs as
                    # methods on the router AND a `Handle("METHOD", "/path",
                    # handler)` shape where the method is the first argument.
                    # Pass `handle_method: "Handle"` so both shapes resolve in
                    # a single parse. httprouter has no groups, so we don't
                    # pass any cross-file group map.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content, handle_method: "Handle")
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route. `find_handler_arg`
                    # in `GoCalleeExtractor` picks the first non-string
                    # positional arg after the path string, which works
                    # for httprouter's both shapes: `r.GET("/x", h)` (path
                    # then handler) and `r.Handle("METHOD", "/x", h)` (two
                    # leading strings then handler).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = Noir::GoCalleeExtractor.function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          last_endpoint = add_endpoint(route.path, route.verb, details)
                          if entries = callees_by_route[route.line]?
                            entries.each do |entry|
                              name, callee_path, callee_line = entry
                              last_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                            end
                          end
                        end
                      end

                      # FormValue must be checked separately to avoid matching PostFormValue
                      if line.includes?("FormValue(") && !line.includes?("PostFormValue(")
                        extract_param(line, /(?<!Post)FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query", last_endpoint)
                      end

                      PARAM_PATTERNS.each do |includes_check, regex, param_type|
                        if line.includes?(includes_check)
                          extract_param(line, regex, param_type, last_endpoint)
                        end
                      end

                      # Stdlib body-decoding idioms used by raw httprouter
                      # handlers. Captures both the JSON-decoder pattern
                      # and `io.ReadAll(r.Body)` raw-byte access.
                      if !last_endpoint.url.empty? &&
                         (line.matches?(/json\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/) ||
                         line.matches?(/(?:io|ioutil)\.ReadAll\([^)]*\.Body\)/))
                        body_param = Param.new("body", "", "json")
                        last_endpoint.params << body_param unless last_endpoint.params.includes?(body_param)
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

      result
    end

    private def add_endpoint(route_path : String, method : String, details : Details) : Endpoint
      if route_path.size > 0
        new_endpoint = Endpoint.new(route_path, method, details)
        result << new_endpoint
        new_endpoint
      else
        Endpoint.new("", "")
      end
    end

    private def extract_param(line : String, regex : Regex, param_type : String, endpoint : Endpoint)
      if param_match = line.match(regex)
        param_name = param_match[1]
        if param_name.size > 0 && !endpoint.url.empty?
          endpoint.params << Param.new(param_name, "", param_type)
        end
      end
    end
  end
end
