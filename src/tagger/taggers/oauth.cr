require "../../models/tagger"
require "../../models/endpoint"

class OAuthTagger < Tagger
  WORDS = Set{
    "grant_type", "code", "redirect_uri", "redirect_url", "client_id", "client_secret",
    "response_type", "scope", "state", "code_challenge", "code_challenge_method",
    "code_verifier", "refresh_token", "access_token", "id_token", "nonce", "audience",
  }

  OAUTH_PATH_PARTS = Set{"oauth", "oauth2", "authorize", "authorization", "token", "callback"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "oauth"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set
      intersection = WORDS & param_names

      # OAuth authorization endpoints commonly use response_type +
      # client_id + redirect_uri, while token endpoints can rely on
      # HTTP Basic auth and expose only grant_type + code/verifier.
      check = strong_oauth_params?(param_names) ||
              (oauth_url?(endpoint.url) && intersection.size >= 3) ||
              (oauth_url?(endpoint.url) && oauth_authorization_params?(param_names)) ||
              (oauth_url?(endpoint.url) && oauth_token_params?(param_names))

      if check
        tag = Tag.new("oauth", "Suspected OAuth endpoint for granting 3rd party access.", "Oauth")
        endpoint.add_tag(tag)
      end
    end
  end

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end

  private def oauth_url?(url : String) : Bool
    parts = url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
    parts.any? { |part| OAUTH_PATH_PARTS.includes?(part) }
  end

  private def oauth_authorization_params?(param_names : Set(String)) : Bool
    param_names.includes?("client_id") &&
      (param_names.includes?("redirect_uri") || param_names.includes?("redirect_url")) &&
      (param_names.includes?("response_type") || param_names.includes?("scope") || param_names.includes?("state"))
  end

  private def strong_oauth_params?(param_names : Set(String)) : Bool
    oauth_authorization_params?(param_names) || strong_oauth_token_params?(param_names)
  end

  private def strong_oauth_token_params?(param_names : Set(String)) : Bool
    return false unless param_names.includes?("grant_type")

    param_names.includes?("client_secret") ||
      param_names.includes?("code_verifier") ||
      param_names.includes?("refresh_token") ||
      (param_names.includes?("client_id") && param_names.includes?("code"))
  end

  private def oauth_token_params?(param_names : Set(String)) : Bool
    return false unless param_names.includes?("grant_type")

    param_names.includes?("client_id") ||
      param_names.includes?("code") ||
      param_names.includes?("code_verifier") ||
      param_names.includes?("refresh_token")
  end
end
