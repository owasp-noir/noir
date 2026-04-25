require "../../../models/analyzer"
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
      },
      nest_methods: Set{"path"},
      transparent_methods: Set{"before", "after", "afterAfter"},
      query_methods: Set{"queryParams", "queryParamOrDefault", "queryParamsValues"},
      header_methods: Set{"headers"},
      cookie_methods: Set{"cookie"},
      body_methods: Set{"body", "bodyAsBytes"},
    )

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = File.read(path, encoding: "utf-8", invalid: :skip)
        next unless SPARK_MARKERS.any? { |m| content.includes?(m) }

        Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(content, CONFIG).each do |route|
          @result << build_endpoint(route, path)
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
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
