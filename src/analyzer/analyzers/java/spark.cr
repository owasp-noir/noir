require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jvm_lambda_dsl_extractor_ts"

module Analyzer::Java
  # Spark Java is Sinatra-flavoured: `Spark.get("/x", (req, res)
  # -> ...)` (or just `get("/x", ...)` after `import static
  # spark.Spark.*`). Path nesting is `path("/api", () -> { ... })`.
  # The shared lambda-DSL extractor handles all of that; this
  # analyzer just supplies the Spark method-name set.
  class Spark < Analyzer
    JAVA_EXTENSION = "java"
    SPARK_MARKERS  = ["spark.Spark", "import static spark.", "import spark."]

    # Spark's request helpers. `body()` returns the raw body string
    # (no type info) — emit a generic body param. `queryParams`
    # serves both query string and form data; we surface it as
    # `query` since Spark callers most commonly read it that way.
    CONFIG = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
      verb_methods: {
        "get"     => "GET",
        "post"    => "POST",
        "put"     => "PUT",
        "delete"  => "DELETE",
        "patch"   => "PATCH",
        "head"    => "HEAD",
        "options" => "OPTIONS",
        "trace"   => "TRACE",
        "connect" => "CONNECT",
        "any"     => "ANY",
      },
      nest_methods: Set{"path"},
      transparent_methods: Set{"before", "after", "afterAfter"},
      query_methods: Set{"queryParams", "queryParamOrDefault", "queryParamsValues"},
      header_methods: Set{"headers"},
      cookie_methods: Set{"cookie"},
      body_methods: Set{"body", "bodyAsBytes"},
      websocket_methods: Set{"webSocket"},
      # `redirect.get("/from", "/to")` & friends register redirect
      # routes with all-string-literal arguments — allowlist the
      # `redirect` receiver so they survive the route/collection-call
      # disambiguation in the shared extractor.
      router_receivers: Set{"redirect"},
    )

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      file_list = all_files()
      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless SPARK_MARKERS.any? { |m| content.includes?(m) }

        Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(content, CONFIG, include_callees: include_callee).each do |route|
          @result << build_endpoint(route, path)
        end

        collect_static_file_endpoints(content).each do |entry|
          endpoint_path, line = entry
          @result << Endpoint.new(endpoint_path, "GET", Details.new(PathInfo.new(path, line)))
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterJvmLambdaDslExtractor::Route, path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      route.path.scan(%r{/:([A-Za-z_][A-Za-z0-9_]*)}) do |match|
        params << Param.new(match[1], "", "path")
      end
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(route.path, route.verb, params, details)
      endpoint.protocol = route.protocol

      # 1-hop callees out of the handler lambda body. The Route
      # extractor doesn't carry the file path, so attach it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end

    private def collect_static_file_endpoints(content : String) : Array(Tuple(String, Int32))
      endpoints = [] of Tuple(String, Int32)
      scan_static_file_call(content, "staticFiles.location", endpoints)
      scan_static_file_call(content, "staticFiles.externalLocation", endpoints)
      scan_static_file_call(content, "staticFileLocation", endpoints)
      scan_static_file_call(content, "externalStaticFileLocation", endpoints)
      endpoints.uniq
    end

    private def scan_static_file_call(content : String,
                                      method_name : String,
                                      endpoints : Array(Tuple(String, Int32)))
      offset = 0
      while marker = content.index(method_name, offset)
        offset = marker + method_name.size
        next unless static_file_call_name?(content, marker, method_name)

        endpoints << {"/**", content[0...marker].count('\n') + 1}
      end
    end

    private def static_file_call_name?(content : String, marker : Int32, method_name : String) : Bool
      before = marker.zero? ? '\0' : content[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = marker + method_name.size
      while after_idx < content.size && content[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < content.size && content[after_idx] == '('
    end
  end
end
