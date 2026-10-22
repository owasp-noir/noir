require "../../engines/javascript_engine"
require "../../../miniparsers/firebase_functions_extractor"

module Analyzer::Javascript
  # Firebase / Cloud Functions HTTPS functions. Each one is served at
  # `https://<region>-<project>.cloudfunctions.net/<exportName>`, so the
  # export name is the path. `onRequest` takes any verb; `onCall` is the
  # callable protocol, a POST whose JSON body wraps the payload in `data`.
  class FirebaseFunctions < JavascriptEngine
    analyzer_for "js_firebase_functions"

    def analyze
      ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
        content = read_file_content(path)
        next if Noir::JSRouteExtractor.test_stub_only?(path, content)
        Noir::FirebaseFunctionsExtractor.extract(content).map { |trigger| endpoint_for(path, trigger) }
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def endpoint_for(path : String, trigger : Noir::FirebaseFunctionsExtractor::Trigger) : Endpoint
      details = Details.new(PathInfo.new(path, trigger.line))
      url = "/#{trigger.name}"
      return Endpoint.new(url, "POST", [Param.new("data", "", "json")], details) unless trigger.kind == "onRequest"

      endpoint = Endpoint.new(url, "ANY", details)
      # An inline `(req, res) => ...` handler reads Express-style request
      # fields; a handler passed by name (an Express `app`) yields none.
      Noir::JSRouteExtractor.extract_query_params(trigger.args, endpoint)
      Noir::JSRouteExtractor.extract_body_params(trigger.args, endpoint)
      Noir::JSRouteExtractor.extract_header_params(trigger.args, endpoint)
      Noir::JSRouteExtractor.extract_cookie_params(trigger.args, endpoint)
      endpoint
    end
  end
end
