require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Beego < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
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
                    content = File.read(path, encoding: "utf-8", invalid: :skip)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          new_endpoint = Endpoint.new(route.path, route.verb, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      ["GetString", "GetStrings", "GetInt", "GetInt8", "GetUint8", "GetInt16", "GetUint16", "GetInt32", "GetUint32",
                       "GetInt64", "GetUint64", "GetBool", "GetFloat"].each do |pattern|
                        match = line.match(/#{pattern}\(\"(.*)\"\)/)
                        if match
                          param_name = match[1]
                          last_endpoint.params << Param.new(param_name, "", "query")
                        end
                      end

                      if line.includes?("GetCookie(")
                        match = line.match(/GetCookie\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
                      end

                      if line.includes?("GetSecureCookie(")
                        match = line.match(/GetSecureCookie\(\"(.*)\"\)/)
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
