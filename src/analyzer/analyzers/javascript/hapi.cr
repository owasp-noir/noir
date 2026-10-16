require "../../engines/javascript_engine"
require "../../../miniparsers/hapi_extractor_ts"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/url_path"
require "./express/router_mount_scanner"

module Analyzer::Javascript
  class Hapi < JavascriptEngine
    analyzer_for "js_hapi"

    JS_EXTENSIONS = [".js", ".mjs", ".cjs", ".ts"]
    # Precompiled once — a single PCRE2-JIT scan replaces five naive
    # String#includes? substring scans over the whole file content.
    # Regex.union auto-escapes each literal (including the parens in
    # "require('hapi')"), so it is provably equivalent to the
    # OR-of-includes? it replaces.
    HAPI_MARKERS_RE = Regex.union("@hapi/hapi", "require('hapi')", "require(\"hapi\")", "from 'hapi'", "from \"hapi\"")

    def analyze
      # A plugin module (`exports.plugin = { register(server) { server.route(…) } }`)
      # never imports hapi, so inside a project whose package.json depends on
      # hapi every file is in scope; elsewhere the import marker decides.
      project_roots = discover_js_project_roots(["@hapi/hapi", "\"hapi\""], [] of String)
      # `server.register(require('./x'), { routes: { prefix } })` prefixes,
      # keyed per plugin file in `CodeLocator`.
      RouterMountScanner.new(all_files, @base_paths, base_path, logger, :hapi).scan
      include_callee = callees_needed?

      per_file = ordered_scan_files(get_files_by_extensions(JS_EXTENSIONS)) do |path|
        content = read_file_content(path)
        # `server.route(...)` in a lab/mocha suite is driven by `server.inject`,
        # never served. Import-blind: `test_stub_only?` would drop a hapi
        # server that also imports axios.
        next if Noir::JSRouteExtractor.test_file?(path, content)
        in_project = !project_roots.empty? && path_under_project_roots?(path, project_roots)
        next unless in_project || content.matches?(HAPI_MARKERS_RE)

        mounts = CodeLocator.instance.all(ExpressConstants.file_key(Noir::PathScope.expand(path)))
        mounts = [""] if mounts.empty?
        Noir::TreeSitterHapiExtractor.extract_routes(content, include_callee).flat_map do |route|
          mounts.map { |prefix| build_endpoint(route, prefix, path, include_callee) }
        end
      end

      per_file.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterHapiExtractor::Route, prefix : String, path : String, include_callee : Bool) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      params << Param.new("body", "", "json") if route.has_body?

      # Hapi serves a plugin's `/` route at the bare prefix.
      url = route.path == "/" && !prefix.empty? ? prefix : Noir::URLPath.join(prefix, route.path)
      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(url, route.verb, params, details)
      attach_route_callees(endpoint, route.callees, path) if include_callee
      endpoint
    end

    private def attach_route_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry), path : String)
      callees.each do |name, _callee_path, line|
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end
    end
  end
end
