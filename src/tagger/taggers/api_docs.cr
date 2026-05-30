require "../../models/tagger"
require "../../models/endpoint"

# Flags API documentation / schema endpoints — Swagger UI, OpenAPI/JSON
# specs, GraphiQL, ReDoc, RapiDoc, WSDL/WADL, Spring `…/api-docs`. These
# expose the full API surface (every route, parameter, and model) and
# are very frequently reachable without authentication, so they are a
# high-value recon target and an information-disclosure risk.
class ApiDocsTagger < Tagger
  # Matched against slash/dot-delimited segments (hyphens and
  # underscores kept inside a segment) so `/swagger-ui.html`,
  # `/v3/api-docs`, and `/openapi.json` are all recognized while a
  # generic `/docs` documentation site is not (FastAPI apps are still
  # caught via `/openapi.json` / `/redoc`).
  DOC_SEGMENTS = Set{
    "swagger", "swagger-ui", "swaggerui", "swagger-resources",
    "openapi", "openapi3", "redoc", "graphiql", "rapidoc",
    "wsdl", "wadl", "api-docs", "api_docs", "apidocs",
    "asyncapi", "api-json", "api-yaml", "apispec", "apispec_1",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "api_docs"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      segments = doc_segments(endpoint.url)
      check = segments.any? { |seg| DOC_SEGMENTS.includes?(seg) } ||
              api_schema?(segments)

      if check
        tag = Tag.new(
          "api_docs",
          "API documentation / schema endpoint (Swagger, OpenAPI, GraphiQL, ReDoc, WSDL); exposes the full API surface and is frequently reachable without authentication — review for unauthenticated exposure and information disclosure.",
          "ApiDocs"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  private def doc_segments(url : String) : Array(String)
    url.downcase.split(/[\/.]+/).reject(&.empty?)
  end

  # `schema` is too generic to match on its own (GraphQL `/schema`,
  # resource schema routes), so only flag it alongside an `api`/`openapi`
  # segment — the drf-spectacular `/api/schema/` shape.
  private def api_schema?(segments : Array(String)) : Bool
    segments.includes?("schema") &&
      (segments.includes?("api") || segments.includes?("openapi"))
  end
end
