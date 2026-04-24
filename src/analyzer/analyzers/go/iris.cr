require "../../engines/go_engine"

module Analyzer::Go
  class Iris < GoEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]

    def analyze
      # Iris uses `.Party(...)` for route groups; pass that into both the
      # engine's fixpoint group collection and the per-file extractor.
      package_groups, file_contents = collect_package_groups_ts_iris
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
                    content = file_contents[path]? || File.read(path, encoding: "utf-8", invalid: :skip)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content, cross_file_groups, group_method: "Party"
                    )
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          normalized = normalize_iris_path(route.path)
                          if route.verb == "ANY"
                            HTTP_METHODS.each do |m|
                              new_endpoint = Endpoint.new(normalized, m, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          else
                            new_endpoint = Endpoint.new(normalized, route.verb, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      ["URLParam", "URLParamDefault", "URLParamTrim",
                       "PostValue", "FormValue",
                       "GetHeader", "GetCookie"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line, pattern), last_endpoint)
                        end
                      end

                      if line.includes?("ReadJSON(")
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
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
        logger.error "Iris analyzer failed: #{e.message}"
        logger.debug e
      end

      result
    end

    # Iris-flavoured version of `GoEngine#collect_package_groups_ts`:
    # runs the cross-file fixpoint against `.Party(...)` instead of
    # `.Group(...)`.
    private def collect_package_groups_ts_iris : Tuple(Hash(String, Hash(String, String)), Hash(String, String))
      package_groups = Hash(String, Hash(String, String)).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents = Hash(String, String).new

      get_files_by_extension(".go").each do |p|
        next if File.directory?(p)
        dir = File.dirname(p)
        files_by_dir[dir] ||= [] of String
        files_by_dir[dir] << p
      end

      files_by_dir.each do |_dir, paths|
        paths.each do |p|
          begin
            file_contents[p] = File.read(p, encoding: "utf-8", invalid: :skip)
          rescue File::NotFoundError
          end
        end
      end

      files_by_dir.each do |dir, paths|
        groups = Hash(String, String).new
        loop do
          prev_size = groups.size
          paths.each do |p|
            content = file_contents[p]?
            next if content.nil?
            found = Noir::TreeSitterGoRouteExtractor.extract_groups(content, groups, "Party")
            found.each { |k, v| groups[k] ||= v }
          end
          break if groups.size == prev_size
        end
        package_groups[dir] = groups unless groups.empty?
      end

      {package_groups, file_contents}
    end

    # Strip Iris type annotations from path params: `{id:uint64}` → `{id}`,
    # `{file:path}` → `{file}`. Leaves unadorned `{id}` untouched.
    def normalize_iris_path(path : String) : String
      path.gsub(/\{([^{}:]+):[^{}]+\}/) { "{#{$1}}" }
    end

    def get_param(line : String, pattern : String) : Param
      param_type = case pattern
                   when "URLParam", "URLParamDefault", "URLParamTrim" then "query"
                   when "PostValue", "FormValue"                      then "form"
                   when "GetHeader"                                   then "header"
                   when "GetCookie"                                   then "cookie"
                   else                                                    "json"
                   end

      # Find the specific call — avoids picking up a different `(` earlier on
      # the line (e.g. `foo(ctx.URLParam("x"))`).
      idx = line.index("#{pattern}(")
      return Param.new("", "", "") if idx.nil?

      after = line[(idx + pattern.size + 1)..]
      close = after.index(")")
      return Param.new("", "", "") if close.nil?

      arg = after[0...close].split(",")[0].gsub("\"", "").strip
      return Param.new("", "", "") if arg.empty?

      Param.new(arg, "", param_type)
    end
  end
end
