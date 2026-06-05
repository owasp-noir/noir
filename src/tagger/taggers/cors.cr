require "../../models/tagger"
require "../../models/endpoint"

class CorsTagger < Tagger
  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "cors"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      # CORS is a header-level concern: `Origin` and the whole
      # `Access-Control-*` family are request/response headers. Matching
      # a bare `origin` query/body param (e.g. `?origin=JFK` on a flights
      # API) was a false positive, so only consider header params. A
      # single CORS-related header is enough to flag the endpoint.
      check = endpoint.params.any? do |param|
        next false unless param.param_type == "header"
        cors_header?(param.name.to_s)
      end

      if check
        tag = Tag.new("cors", "CORS endpoint enabling cross-origin requests, allowing web applications from different domains to interact.", "CORS")
        endpoint.add_tag(tag)
      end
    end
  end

  # Matches the `Origin` request header and the full `Access-Control-*`
  # family (`...-allow-origin`, `...-allow-credentials`, `...-allow-methods`,
  # `...-allow-headers`, `...-expose-headers`, `...-max-age`,
  # `...-request-method`, `...-request-headers`). Underscore variants and
  # the CGI-style `HTTP_ORIGIN` are normalized so they match too.
  private def cors_header?(name : String) : Bool
    normalized = name.downcase.tr("_", "-")
    normalized == "origin" ||
      normalized == "http-origin" ||
      normalized.starts_with?("access-control-")
  end
end
