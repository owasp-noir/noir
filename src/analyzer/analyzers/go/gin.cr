require "../../engines/go_engine"

module Analyzer::Go
  class Gin < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_lines_cache = collect_package_groups
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
                    # Use cached lines from pre-scan, or read if not cached
                    lines = file_lines_cache[path]? || File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    groups = groups_for_directory(package_groups, File.dirname(path))

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      # Use case-insensitive regex for HTTP method detection
                      # Matches patterns like: .GET(, .Get(, .get(, .POST(, .Post(, .post(, etc.
                      # Exclude parameter extraction patterns like Header.Get(, Cookie.Get(, etc.
                      if !line.includes?("Header.Get") && !line.includes?("Cookie.Get") &&
                         (match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/i))
                        method = match[1].upcase
                        get_route_path(line, groups).tap do |route_path|
                          # Handle multi-line routes - check next lines if route is empty
                          if route_path.size == 0 && index + 1 < lines.size
                            next_line = lines[index + 1]
                            route_path = get_route_path(next_line, groups)
                          end

                          if route_path.size > 0
                            new_endpoint = Endpoint.new("#{route_path}", method, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
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

                      if line.includes?("Cookie(")
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
