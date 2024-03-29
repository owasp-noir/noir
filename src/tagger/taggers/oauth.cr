require "../../models/tagger"
require "../../models/endpoint"

class OAuthTagger < Tagger
  WORDS = ["grant_type", "code", "redirect_uri", "client_id", "client_secret"]

  def initialize(options : Hash(Symbol, String))
    super
    @name = "oauth"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      endpoint.params.each do |param|
        tmp_params.push param.name.to_s
      end

      # Check that at least three parameters match.
      check = (WORDS & tmp_params).size >= 3

      if check
        tag = Tag.new("oauth", "Suspected OAuth endpoint for granting 3rd party access.", "Oauth")
        endpoint.add_tag(tag)
      end
    end
  end
end
