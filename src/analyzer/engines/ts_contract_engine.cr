require "./javascript_engine"
require "../../miniparsers/js_route_extractor"
require "../../miniparsers/ts_contract_extractor"

module Analyzer::Typescript
  # Shared base of the contract-first TypeScript routers (ts-rest, oRPC,
  # Effect HttpApi): every source the adapter accepts
  # goes through its `Noir::TSContractExtractor` entry point.
  abstract class TSContractEngine < Analyzer::Javascript::JavascriptEngine
    # Whether a file is worth parsing for this framework.
    abstract def candidate?(content : String) : Bool
    abstract def routes(content : String) : Array(Noir::TSContractExtractor::Route)

    def analyze
      ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
        content = read_file_content(path)
        next unless candidate?(content)
        next if Noir::JSRouteExtractor.test_stub_only?(path, content)
        routes(content).map do |route|
          endpoint = Endpoint.new(route.path, route.method, Details.new(PathInfo.new(path, route.line)))
          route.params.each { |name, type| endpoint.push_param(Param.new(name, "", type)) }
          endpoint
        end
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end
  end
end
