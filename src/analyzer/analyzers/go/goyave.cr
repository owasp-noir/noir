require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Goyave < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Goyave
      # doesn't use the route extractor's cross-file group fixpoint, so
      # we build the file_contents hash via a dedicated helper rather
      # than piggy-backing on `collect_package_groups_ts`.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_filtered_files(channel, ".go")

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path)
                    content = read_file_content(path)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Goyave uses `router.Subrouter("/api")` (single-arg) for
                    # prefix groups and `v1 := api.Group()` (zero-arg) as an
                    # alias that inherits the parent's prefix. The TS
                    # extractor models both via `group_method: "Subrouter"`
                    # plus `group_aliases: ["Group"]`.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content,
                      group_method: "Subrouter",
                      group_aliases: ["Group"],
                      extra_verbs: ["Route"],
                    )
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes(content, path, route_rows, external_fns)

                    # `router.Static(&fs, "/prefix", false)` — the first
                    # `/`-prefixed string arg is both URL prefix and (with
                    # leading slash stripped) disk path.
                    Noir::TreeSitterGoRouteExtractor.extract_goyave_statics(content).each do |sp|
                      public_dirs << {"static_path" => sp.url_prefix, "file_path" => sp.disk_path}
                    end

                    lines.each_index do |index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          # Goyave's `.Route(...)` decorator accepts any
                          # method; map it to a generic "ANY" like the
                          # legacy analyzer did. All other verbs pass
                          # through (already upcased by the extractor).
                          verb = route.verb == "ROUTE" ? "ANY" : route.verb
                          # Strip type patterns from path params for the
                          # URL (e.g. `/product/{id:[0-9]+}` -> `/product/{id}`).
                          clean_path = route.path.gsub(/\{([a-zA-Z0-9_]+):[^}]+\}/, "{\\1}")

                          new_endpoint = Endpoint.new(clean_path, verb, details)
                          if entries = callees_by_route[route.line]?
                            entries.each do |entry|
                              name, callee_path, callee_line = entry
                              new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                            end
                          end
                          result << new_endpoint
                          last_endpoint = new_endpoint

                          route.path.scan(/\{([a-zA-Z0-9_]+)(?::([^}]+))?\}/) do |match_data|
                            param_name = match_data[1]
                            param_pattern = match_data[2]?
                            last_endpoint.params << Param.new(param_name, param_pattern || "", "path")
                          end
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
