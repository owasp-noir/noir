require "../../engines/go_engine"

module Analyzer::Go
  class Iris < GoEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]

    # Iris uses `.Party(...)` for route grouping instead of Gin/Echo's `.Group(...)`.
    # The group resolution logic is otherwise identical, so reuse the extractor
    # shape and swap the detection marker.
    def analyze_group(line : String, lexer : GolangLexer, groups : Array(Hash(String, String)))
      return unless line.includes?(".Party(")

      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      group_name = ""
      group_path = ""
      map.each do |token|
        if token.type == :assign
          group_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
        end

        if token.type == :string
          group_path = token.value.to_s
          groups.each do |group|
            group.each do |key, value|
              if before.value.to_s.includes? key
                group_path = value + group_path
              end
            end
          end
        end

        before = token
      end

      if group_name.size > 0 && group_path.size > 0
        unless groups.any?(&.has_key?(group_name))
          groups << {
            group_name => group_path,
          }
        end
      end
    end

    def analyze
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
                    lines = file_lines_cache[path]? || File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    groups = groups_for_directory(package_groups, File.dirname(path))

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Exclude helpers that collide with HTTP verb regex:
                      # ctx.Request().Header.Get, ctx.GetHeader, ctx.GetCookie.
                      if !line.includes?("Header.Get") && !line.includes?("GetHeader") &&
                         !line.includes?("GetCookie") && !line.includes?(".Party(") &&
                         (match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|ANY)\s*\(/i))
                        method = match[1].upcase
                        get_route_path(line, groups).tap do |route_path|
                          if route_path.size == 0 && index + 1 < lines.size
                            next_line = lines[index + 1]
                            route_path = get_route_path(next_line, groups)
                          end

                          if route_path.size > 0
                            normalized = normalize_iris_path(route_path)
                            if method == "ANY"
                              HTTP_METHODS.each do |m|
                                new_endpoint = Endpoint.new(normalized, m, details)
                                result << new_endpoint
                                last_endpoint = new_endpoint
                              end
                            else
                              new_endpoint = Endpoint.new(normalized, method, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
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
        logger.debug e
      end

      result
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
