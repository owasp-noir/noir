require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./starlette_endpoint_support"
require "../../../detector/detectors/python/fastmcp"

module Analyzer::Python
  class FastMCP < PythonEngine
    include StarletteEndpointSupport
    analyzer_for "python_fastmcp"

    # Reference: https://gofastmcp.com/deployment/running-server#custom-routes
    #
    # `@server.custom_route(path, methods=[...])` adds a Starlette route to
    # the server's HTTP app, beside the MCP endpoint. Only a receiver that
    # resolves, by Python's scope rules, to a name bound from `FastMCP(...)`
    # counts, so another object's `custom_route` is not a route. The handler
    # is a Starlette endpoint `(request)`, read like Starlette's own.

    # `from fastmcp import FastMCP as MCP`, also inside a parenthesized import.
    ALIAS_RE     = /^\s*from\s+(?:fastmcp|mcp\.server\.fastmcp)(?:\.[\w.]+)?\s+import\s+\(?[^)]*?\bFastMCP\s+as\s+([A-Za-z_]\w*)/m
    CUSTOM_ROUTE = {"custom_route" => "GET"}

    def analyze
      ordered_parallel_analyze(python_source_files) do |path|
        analyze_file(path, python_base_path_for(path))
      end.each { |endpoints| result.concat(endpoints) }
      result
    end

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("custom_route") && source.matches?(Detector::Python::FastMCP::IMPORT_RE)

      constructors = ["FastMCP"]
      source.scan(ALIAS_RE) { |m| constructors << m[1] }
      bindings = Hash(Tuple(Int32, ::String), Array(::String)).new
      Noir::TreeSitterPythonRouteExtractor.extract_name_bindings(source).each do |binding|
        (bindings[{binding.scope_row, binding.name}] ||= [] of ::String) << binding.callee
      end
      servers = bindings.select { |_, callees| callees.any? { |callee| constructors.includes?(callee) } }.keys.map(&.[1]).uniq!.sort!
      return if servers.empty?

      lines = source.lines
      endpoints = [] of Endpoint
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, router_names: servers, extra_attributes: CUSTOM_ROUTE).each do |deco|
        next unless deco.attribute_name == "custom_route" && deco.def_line >= 0
        next unless fastmcp_server?(deco, bindings, constructors)

        handler_params = [] of Param
        callees = [] of Callee
        if request_name = parse_function_def(lines, deco.def_line).try(&.params.map(&.name).find { |name| name != "self" && name != "cls" })
          handler_params, callees = starlette_handler_context(lines, deco.def_line, request_name, path,
            definition_base_path: base_path, source: source)
        end

        url = normalize_route_url("", deco.path)
        deco.methods.uniq.each do |method|
          params = extract_path_params(deco.path)
          handler_params.each { |param| add_unique(params, param) }
          endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
          callees.each { |callee| endpoint.push_callee(callee) }
          endpoints << endpoint
        end
      end
      endpoints
    end

    # The receiver's nearest binding, innermost function first, then module
    # level, must include a `FastMCP(...)` call.
    private def fastmcp_server?(deco : Noir::TreeSitterPythonRouteExtractor::Decoration,
                                bindings : Hash(Tuple(Int32, ::String), Array(::String)),
                                constructors : Array(::String)) : Bool
      (deco.scope_rows + [-1]).each do |row|
        if callees = bindings[{row, deco.router_name}]?
          return callees.any? { |callee| constructors.includes?(callee) }
        end
      end
      false
    end
  end
end
