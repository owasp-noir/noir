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
    analyzer_for "java_spark"

    # `spark.Spark` must not be the tail of a longer package such as
    # `org.apache.spark.SparkConf` (Apache Spark, the data engine).
    SPARK_MARKERS = /(?<![\w.])spark\.Spark\b|import static spark\.|import spark\./

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
      query_methods: Set{"queryParams", "queryParamOrDefault", "queryParamsValues", "queryMap"},
      header_methods: Set{"headers"},
      cookie_methods: Set{"cookie"},
      body_methods: Set{"body", "bodyAsBytes"},
      websocket_methods: Set{"webSocket"},
      # `redirect.get("/from", "/to")` & friends register redirect
      # routes with all-string-literal arguments — allowlist the
      # `redirect` receiver so they survive the route/collection-call
      # disambiguation in the shared extractor.
      router_receivers: Set{"redirect"},
      static_methods: {
        "location"                   => "staticFiles",
        "externalLocation"           => "staticFiles",
        "staticFileLocation"         => nil,
        "externalStaticFileLocation" => nil,
      },
    )

    def analyze
      include_callee = callees_needed?
      per_file = ordered_scan_files(get_files_by_extension(".java")) do |path|
        next if JavaEngine.test_path?(base_relative_path(path))

        content = read_file_content(path)
        next unless content.matches?(SPARK_MARKERS)

        Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(content, CONFIG, include_callees: include_callee).map do |route|
          build_endpoint(route, path)
        end
      end

      per_file.each { |endpoints| @result.concat(endpoints) }
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
  end
end
