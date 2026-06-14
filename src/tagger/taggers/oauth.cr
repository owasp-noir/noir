require "../../models/tagger"
require "../../models/endpoint"

class OAuthTagger < Tagger
  WORDS = Set{
    "grant_type", "code", "redirect_uri", "redirect_url", "client_id", "client_secret",
    "response_type", "scope", "state", "code_challenge", "code_challenge_method",
    "code_verifier", "refresh_token", "access_token", "id_token", "nonce", "audience",
    "device_code",
  }

  # URL path segments that, on their own, strongly imply an OAuth/OIDC
  # surface. Any OAuth parameter alongside one of these is enough.
  STRONG_URL_PARTS = Set{"oauth", "oauth2", "oauth20", "openid", "oidc"}

  # URL path segments shared with non-OAuth routes — a CSRF/email "token",
  # a payment "callback", a generic "authorize". These need corroborating
  # parameters before flagging.
  WEAK_URL_PARTS = Set{"authorize", "authorization", "token", "callback"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "oauth"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set
      intersection = WORDS & param_names

      # Match against the URL path only — a host like `oauth.example.com`
      # or `token.example.com` must not make every API route look like an
      # OAuth endpoint.
      parts = path_parts(endpoint.url)
      strong_url = parts.any? { |part| STRONG_URL_PARTS.includes?(part) }
      # A strong URL part implies a weak match too (e.g. `/oauth/token`).
      weak_url = strong_url || parts.any? { |part| WEAK_URL_PARTS.includes?(part) }

      # OAuth authorization endpoints commonly use response_type +
      # client_id + redirect_uri, while token endpoints can rely on
      # HTTP Basic auth and expose only grant_type + code/verifier.
      check = # A whole `/oauth|/oauth2|/openid|/oidc` path segment is an
              # unambiguous OAuth surface on its own — the host is already
              # stripped, so this can't fire on `oauth.example.com`. Catches
              # the param-less endpoints real OAuth servers expose (the
              # `/oauth2/auth` authorize redirect, `/oauth2/device/verify`,
              # `/oauth2/sessions/logout`, a GET on `/oauth2/register/{id}`).
              strong_oauth_segment?(endpoint.url) ||
              strong_oauth_params?(param_names) ||
              # Under an unambiguous /oauth|/openid path, a single OAuth
              # parameter is enough (device-flow `device_code`, an
              # authorize page's `client_id`, a callback's `code`).
              (strong_url && !intersection.empty?) ||
              (weak_url && intersection.size >= 3) ||
              (weak_url && oauth_authorization_params?(param_names)) ||
              (weak_url && oauth_token_params?(param_names)) ||
              # The authorization-code redirect handler — `/callback` (or
              # `/auth/<provider>/callback`) receiving `code` + `state`.
              oauth_callback?(parts, param_names)

      if check
        tag = Tag.new("oauth", "Suspected OAuth endpoint for granting 3rd party access.", "Oauth")
        endpoint.add_tag(tag)
      end
    end
  end

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end

  # The URL's path with scheme/host/query/fragment stripped and lowercased.
  private def path_only(url : String) : String
    path = url.strip

    if scheme_index = path.index("://")
      remainder = path[(scheme_index + 3)..]
      if slash_index = remainder.index("/")
        path = remainder[slash_index..]
      else
        path = ""
      end
    end

    path = path.split("?", 2)[0]
    path = path.split("#", 2)[0]
    path.downcase
  end

  # Split the path into `/`-`-`-`_`-`.`-delimited tokens (the loose form used
  # for the param-corroborated checks).
  private def path_parts(url : String) : Array(String)
    path_only(url).split(/[\/\-_\.]+/).reject(&.empty?)
  end

  # True when a whole `/`-delimited path segment is itself a strong OAuth
  # marker. Unlike `path_parts`, this does NOT split on `-`/`_`/`.`, so the
  # OIDC discovery document `/.well-known/openid-configuration` (segment
  # `openid-configuration`, not `openid`) stays untagged while a param-less
  # `/oauth2/auth` is caught.
  private def strong_oauth_segment?(url : String) : Bool
    path_only(url).split("/").any? { |seg| STRONG_URL_PARTS.includes?(seg) }
  end

  private def oauth_callback?(parts : Array(String), param_names : Set(String)) : Bool
    return false unless parts.includes?("callback")
    param_names.includes?("code") && param_names.includes?("state")
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
      param_names.includes?("device_code") ||
      (param_names.includes?("client_id") && param_names.includes?("code"))
  end

  private def oauth_token_params?(param_names : Set(String)) : Bool
    return false unless param_names.includes?("grant_type")

    param_names.includes?("client_id") ||
      param_names.includes?("code") ||
      param_names.includes?("code_verifier") ||
      param_names.includes?("device_code") ||
      param_names.includes?("refresh_token")
  end
end
