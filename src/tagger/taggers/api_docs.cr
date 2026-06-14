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
    "swagger", "swagger-ui", "swagger-resources",
    "openapi", "openapi3", "redoc", "graphiql", "rapidoc",
    "wsdl", "wadl", "api-docs", "api-doc",
    "asyncapi", "api-json", "api-yaml", "apispec", "apispec_1",
    # OAuth/OIDC/SMART discovery documents — machine-readable service
    # descriptions in the same class as WSDL/OpenAPI. They enumerate the
    # auth surface (every endpoint, supported scopes/grants, jwks_uri) and
    # are almost always unauthenticated, so they are a first-stop recon
    # target. Served both at `/.well-known/<name>` and bare `/<name>`; the
    # names are specific enough to carry no benign collision.
    "openid-configuration", "oauth-authorization-server",
    "oauth-protected-resource", "smart-configuration",
  }

  # Separator-insensitive lookup so `/swagger_ui`, `/swaggerui`,
  # `/open-api`, and `/api_docs` all match regardless of whether the
  # source used `-`, `_`, or no separator at all.
  DOC_SEGMENTS_NORMALIZED = DOC_SEGMENTS.map(&.gsub(/[-_]/, "")).to_set

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "api_docs"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      segments = doc_segments(endpoint.url)
      check = segments.any? { |seg| DOC_SEGMENTS_NORMALIZED.includes?(seg.gsub(/[-_]/, "")) } ||
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
  # resource schema routes), so only flag the drf-spectacular
  # `/api/schema/` shape: a `schema` segment directly preceded by an
  # `api`/`openapi` token or a version token (`/api/v1/schema`). This
  # keeps the documentation endpoint while excluding data-schema
  # sub-resources like `/api/forms/{id}/schema` that merely return a
  # JSON Schema for a resource.
  private def api_schema?(segments : Array(String)) : Bool
    idx = segments.index("schema")
    return false unless idx
    return false unless segments.includes?("api") || segments.includes?("openapi")

    prev = idx > 0 ? segments[idx - 1] : nil
    return false unless prev
    prev == "api" || prev == "openapi" || version_segment?(prev)
  end

  # A version path token such as `v1`, `v2`, `v10`.
  private def version_segment?(segment : String) : Bool
    !!(segment =~ /\Av\d+\z/)
  end
end
