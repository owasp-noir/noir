require "../../../models/analyzer"
require "../../../miniparsers/jvm_lambda_dsl_extractor_ts"

module Analyzer::Java
  # Javalin runs on the lambda-DSL routing style:
  # `app.get("/x", ctx -> ...)` and `path("/api", () -> { ... })`
  # nested via `app.routes(() -> { ... })`. The shared
  # `TreeSitterJvmLambdaDslExtractor` does the heavy lifting; this
  # analyzer just supplies the Javalin method-name set and turns
  # the raw scan results into `Endpoint`s.
  class Javalin < Analyzer
    JAVA_EXTENSION  = "java"
    JAVALIN_MARKERS = ["io.javalin"]

    # Javalin's request-context helpers. `header` and `cookie`
    # double as response setters, but using them with a single
    # string argument is overwhelmingly the read path — false
    # positives here are cheap (a benign extra param to scan).
    CONFIG = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
      verb_methods: {
        "get"     => "GET",
        "post"    => "POST",
        "put"     => "PUT",
        "delete"  => "DELETE",
        "patch"   => "PATCH",
        "head"    => "HEAD",
        "options" => "OPTIONS",
      },
      nest_methods: Set{"path"},
      transparent_methods: Set{"routes", "before", "after"},
      query_methods: Set{"queryParam", "queryParamAsClass"},
      form_methods: Set{"formParam", "formParamAsClass"},
      header_methods: Set{"header"},
      cookie_methods: Set{"cookie"},
      body_methods: Set{"body", "bodyAsBytes", "bodyAsInputStream"},
      body_typed_methods: Set{"bodyAsClass", "bodyValidator", "bodyStreamAsClass"},
    )

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless JAVALIN_MARKERS.any? { |m| content.includes?(m) }

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
      route.form_params.each { |name| params << Param.new(name, "", "form") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      if route.has_body?
        params << Param.new("body", route.body_type || "", "json")
      end

      details = Details.new(PathInfo.new(path, route.line + 1))
      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
