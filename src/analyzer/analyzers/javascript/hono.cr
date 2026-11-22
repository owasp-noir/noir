require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/ts_contract_extractor"
require "./express/router_mount_scanner"

module Analyzer::Javascript
  class Hono < JavascriptEngine
    analyzer_for "js_hono"

    def analyze
      scan_for_router_mounts
      # HonoX mounts a route module's `new Hono()` app at the module's file
      # path (js_honox); read here, its routes would lose that prefix.
      honox = js_package_owners(["\"honox\""])

      # Per-file results merged below in input order, not appended to a
      # shared array from the workers: worker completion order varies run
      # to run (see `Analyzer#ordered_scan_files`), and the static-dir
      # merge is first-wins.
      per_file = ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
        next if base_relative_path(path).includes?("/app/routes/") && owned_by_js_package?(path, honox)
        result = [] of Endpoint
        static_dirs = [] of Hash(String, String)
        source = read_file_content(path)
        content = Noir::JSRouteExtractor.strip_js_comments(source)
        next if Noir::JSRouteExtractor.other_shared_extractor_framework?(content, :hono)
        include_callee = callees_needed?
        callees_by_route = include_callee ? Noir::JSCalleeExtractor.callees_for_routes(content, path) : {} of String => Array(Noir::JSCalleeExtractor::Entry)
        parser_endpoints = Noir::JSRouteExtractor.extract_routes(path, content, @is_debug,
          include_callees: include_callee, route_callees: callees_by_route, on_routes: true)
        parser_endpoints.each do |endpoint|
          extract_path_params(endpoint)
          result << endpoint
        end

        contracts = if Noir::TSContractExtractor.hono_candidate?(content) &&
                       !Noir::JSRouteExtractor.test_stub_only?(path, content) &&
                       !Noir::JSRouteExtractor.minified_content?(content)
                      Noir::TSContractExtractor.hono_file(source, path, descriptors: content.includes?("@hono/zod-openapi"))
                    end
        collect_static_paths(path, content, static_dirs, :hono)
        {result, static_dirs, contracts}
      rescue e
        logger.debug "Parser failed for #{path}: #{e.message}, falling back to regex"
        partial = result || [] of Endpoint
        analyze_with_regex(path, partial)
        {partial, static_dirs || [] of Hash(String, String), nil}
      end

      result = per_file.flat_map(&.[0])
      static_dirs = per_file.flat_map(&.[1]).uniq! { |dir| {dir["static_path"], dir["file_path"]} }

      result.concat(openapi_endpoints(per_file.compact_map(&.[2])))
      process_js_static_dirs(static_dirs, result)

      result
    end

    private def openapi_endpoints(files : Array(Noir::TSContractExtractor::HonoFile)) : Array(Endpoint)
      files.each do |file|
        file.file_prefixes = CodeLocator.instance.all(ExpressConstants.file_key(Noir::PathScope.expand(file.path)))
      end
      registrations = Noir::TSContractExtractor.hono_endpoints(files) do |path, specifier|
        Noir::ImportGraph.resolve_relative_import(path, specifier, boundary: configured_base_for(path))
      end
      registrations.map do |registration|
        route = registration.route
        url = Noir::URLPath.join(registration.prefix, route.path)
        location = PathInfo.new(registration.file, registration.line)
        location.route_middleware = registration.middleware
        endpoint = Endpoint.new(url, route.method, Details.new(location))
        endpoint.resolution = {"registration" => Endpoint::RESOLUTION_UNRESOLVED} if registration.unresolved
        url.scan(/\{(\w+)\}/) { |pm| endpoint.push_param(Param.new(pm[1], "", "path")) }
        route.params.each { |name, type| endpoint.push_param(Param.new(name, "", type)) }
        endpoint
      end
    end

    private def analyze_with_regex(path : String, result : Array(Endpoint))
      last_endpoint = Endpoint.new("", "")
      file_content = read_file_content(path)

      file_content.each_line.with_index do |line, index|
        endpoints = line_to_endpoints(line)
        endpoints.each do |endpoint|
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          result << endpoint
          last_endpoint = endpoint
        end

        line_to_params(line).each do |param|
          unless last_endpoint.method.empty?
            last_endpoint.push_param(param)
          end
        end
      end
    end

    private def extract_path_params(endpoint : Endpoint)
      if endpoint.url.includes?(":")
        endpoint.url.scan(/:(\w+)/) do |m|
          if m.size > 0
            param = Param.new(m[1], "", "path")
            endpoint.push_param(param)
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

    HTTP_METHODS = %w[get post put delete patch options head query]
    # Compiled once — an interpolated regex literal would otherwise be
    # rebuilt (full PCRE2 compile) for every method on every line.
    ROUTE_CALL_RES = HTTP_METHODS.map { |m| {m, /\b(?:app|router|hono)\s*\.\s*#{m}\s*\(\s*['"]([^'"]+)['"]/} }.to_h

    def line_to_endpoints(line : String) : Array(Endpoint)
      http_methods = HTTP_METHODS

      http_methods.each do |method|
        if line =~ ROUTE_CALL_RES[method]
          path = $1
          return [Endpoint.new(path, method.upcase)]
        end
      end

      # app.all('/path', ...) - registers for all HTTP methods
      if line =~ /\b(?:app|router|hono)\s*\.\s*all\s*\(\s*['"]([^'"]+)['"]/
        path = $1
        return %w[get post put delete patch options head].map { |m| Endpoint.new(path, m.upcase) }
      end

      # app.on('GET', '/path', ...) - single method string
      if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*['"](\w+)['"]\s*,\s*['"]([^'"]+)['"]/
        method = $1.downcase
        path = $2
        if http_methods.includes?(method)
          return [Endpoint.new(path, method.upcase)]
        end
      end

      # app.on(['GET', 'POST'], '/path', ...) - array of methods
      if line =~ /\b(?:app|router|hono)\s*\.\s*on\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]/
        methods_str = $1
        path = $2
        endpoints = [] of Endpoint
        methods_str.scan(/['"](\w+)['"]/) do |m|
          method = m[1].downcase
          if http_methods.includes?(method) && !endpoints.any? { |e| e.method == method.upcase }
            endpoints << Endpoint.new(path, method.upcase)
          end
        end
        return endpoints unless endpoints.empty?
      end

      [] of Endpoint
    end

    private def scan_for_router_mounts
      scanner = RouterMountScanner.new(all_files, @base_paths, base_path, logger, :hono)
      scanner.scan
    end
  end
end
