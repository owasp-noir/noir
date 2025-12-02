require "../../models/tagger"
require "../../models/endpoint"

class JwtTagger < Tagger
  WORDS = ["token", "jwt", "bearer", "refresh_token", "access_token", "id_token", "authorization"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "jwt"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      endpoint.params.each do |param|
        tmp_params.push param.name.to_s.downcase
      end

      # Check URL path for JWT indicators
      url_lower = endpoint.url.downcase
      is_jwt_url = url_lower.includes?("/token") || url_lower.includes?("/auth") || url_lower.includes?("/jwt") || url_lower.includes?("/refresh")

      words_set = Set.new(WORDS)
      tmp_params_set = Set.new(tmp_params)
      intersection = words_set & tmp_params_set

      # Check that at least two parameters match or URL indicates JWT handling
      check = intersection.size.to_i >= 2 || (is_jwt_url && intersection.size.to_i >= 1)

      if check
        tag = Tag.new("jwt", "JWT endpoint for token-based authentication, requiring validation of signature, expiration, and claims.", "JWT")
        endpoint.add_tag(tag)
      end
    end
  end
end
