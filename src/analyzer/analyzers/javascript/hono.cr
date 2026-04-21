require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Hono < JavascriptEngine
    def analyze
      result = [] of Endpoint
      static_dirs = [] of Hash(String, String)

      parallel_file_scan do |path|
        begin
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug)
          parser_endpoints.each do |endpoint|
            details = Details.new(PathInfo.new(path, 1))
            endpoint.details = details

            extract_path_params(endpoint)
            result << endpoint
          end

          # Extract app.on() patterns not handled by JSRouteExtractor
          extract_on_routes(path, content, result)

          Noir::JSRouteExtractor.extract_static_paths(content).each do |static_path|
            static_dirs << static_path unless static_dirs.any? { |s| s["static_path"] == static_path["static_path"] && s["file_path"] == static_path["file_path"] }
          end
        rescue e
          logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
          analyze_with_regex(path, result)
        end
      end

      process_static_dirs(static_dirs, result)

      result
    end

    private def process_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint))
      static_dirs.each do |dir|
        full_path = (base_path + "/" + dir["file_path"]).gsub_repeatedly("//", "/")
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        get_files_by_prefix(full_path).each do |file_path|
          if File.exists?(file_path)
            relative_path = file_path.starts_with?(full_path) ? file_path.lchop(full_path) : file_path
            url = static_path == "/" ? relative_path : "#{static_path}#{relative_path}"
            url = "/#{url}" unless url.starts_with?("/")

            details = Details.new(PathInfo.new(file_path))
            endpoint = Endpoint.new(url, "GET", details)
            result << endpoint unless result.any? { |e| e.url == url && e.method == "GET" }
          end
        end
      end
    end

    private def extract_on_routes(path : String, content : String, result : Array(Endpoint))
      http_methods = %w[get post put delete patch options head]
      lines = content.lines
      lines.each_with_index do |line, index|
        # app.on('GET', '/path', ...) or app.on("GET", "/path", ...)
        if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*['"](\w+)['"]\s*,\s*['"]([^'"]+)['"]/
          method = $1.downcase
          url = $2
          if http_methods.includes?(method)
            unless result.any? { |e| e.url == url && e.method == method.upcase }
              endpoint = Endpoint.new(url, method.upcase)
              details = Details.new(PathInfo.new(path, index + 1))
              endpoint.details = details

              # Extract params from subsequent lines in the handler body
              ((index + 1)...lines.size).each do |i|
                handler_line = lines[i]
                break if handler_line =~ /^\s*\}\s*\)\s*$/
                line_to_params(handler_line).each do |param|
                  endpoint.push_param(param)
                end
              end

              extract_path_params(endpoint)

              result << endpoint
            end
          end
        end
      end
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        last_endpoint = Endpoint.new("", "")
        file_content = file.gets_to_end

        file_content.each_line.with_index do |line, index|
          endpoints = line_to_endpoints(line)
          endpoints.each do |endpoint|
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint.details = details
            result << endpoint
            last_endpoint = endpoint
          end

          line_to_params(line).each do |param|
            if last_endpoint.method != ""
              last_endpoint.push_param(param)
            end
          end
        end
      end
    end

    private def extract_path_params(endpoint : Endpoint)
      if endpoint.url.includes?(":")
        endpoint.url.scan(/:(\w+)/) do |m|
          if m.size > 0
            param = Param.new(m[1], "", "path")
            endpoint.push_param(param) if !endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
          end
        end
      end
    end

    def line_to_params(line : String) : Array(Param)
      # c.req.query('param') - any variable name (c, ctx, context, etc.)
      if line =~ /\w+\.req\.query\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "query")]
      end

      # c.req.queries('param') - returns array
      if line =~ /\w+\.req\.queries\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "query")]
      end

      # c.req.param('id')
      if line =~ /\w+\.req\.param\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "path")]
      end

      # c.req.header('X-Custom')
      if line =~ /\w+\.req\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "header")]
      end

      # await c.req.json() destructuring: const { name, email } = await c.req.json()
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.json\s*\(/
        return $1.split(",").map(&.strip).reject(&.empty?).map { |name| Param.new(name, "", "json") }
      end

      # c.req.parseBody() destructuring
      if line =~ /(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.parseBody\s*\(/
        return $1.split(",").map(&.strip).reject(&.empty?).map { |name| Param.new(name, "", "form") }
      end

      # Cookie: getCookie(c, 'name') from hono/cookie
      if line =~ /getCookie\s*\(\s*\w+\s*,\s*['"]([^'"]+)['"]\s*\)/
        return [Param.new($1, "", "cookie")]
      end

      [] of Param
    end

    def line_to_endpoints(line : String) : Array(Endpoint)
      http_methods = %w[get post put delete patch options head]

      http_methods.each do |method|
        if line =~ /\b(?:app|router|hono)\s*\.\s*#{method}\s*\(\s*['"]([^'"]+)['"]/
          path = $1
          return [Endpoint.new(path, method.upcase)]
        end
      end

      # app.all('/path', ...) - registers for all HTTP methods
      if line =~ /\b(?:app|router|hono)\s*\.\s*all\s*\(\s*['"]([^'"]+)['"]/
        path = $1
        return http_methods.map { |m| Endpoint.new(path, m.upcase) }
      end

      # app.on('GET', '/path', ...) or app.on(['GET', 'POST'], '/path', ...)
      if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*['"](\w+)['"]\s*,\s*['"]([^'"]+)['"]/
        method = $1.downcase
        path = $2
        if http_methods.includes?(method)
          return [Endpoint.new(path, method.upcase)]
        end
      end

      [] of Endpoint
    end
  end
end
