require "../../engines/go_engine"

module Analyzer::Go
  class Gin < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts
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

                    # Tree-sitter pre-pass: harvest every verb route with its
                    # group-resolved path in one go. Indexed by line so the
                    # line loop below can attribute body params (Query/PostForm
                    # /GetHeader/Cookie) to the most recently declared route —
                    # matching the legacy `last_endpoint` semantics.
                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Emit endpoints for any verb route that begins on this
                      # line. Gin allows the same verb method name upper/lower
                      # (`r.GET` vs `r.Get`); both are covered by the TS
                      # extractor's HTTP_VERB_METHODS set.
                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          new_endpoint = Endpoint.new(route.path, route.verb, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      ["Query", "PostForm", "GetHeader"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Static(")
                        add_static_path_if_valid(get_static_path(line), public_dirs)
                      end

                      if line.includes?("Cookie(") &&
                         !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
                        match = line.match(/Cookie\(\"(.*)\"\)/)
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
      param_type = "json"
      if line.includes?("Query(")
        param_type = "query"
      end
      if line.includes?("PostForm(")
        param_type = "form"
      end
      if line.includes?("GetHeader(")
        param_type = "header"
      end

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          if line.includes?("DefaultQuery") || line.includes?("DefaultPostForm")
            param_name = second[0].split(",")[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          else
            param_name = second[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          end

          return rtn
        end
      end

      Param.new("", "", "")
    end
  end
end
