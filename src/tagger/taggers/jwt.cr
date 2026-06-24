require "../../models/tagger"
require "../../models/endpoint"

class JwtTagger < Tagger
  STRONG_NAMES = Set{
    "jwt", "bearer", "authorization", "access_token", "refresh_token", "id_token",
    "auth_token", "api_token", "x_api_token", "x_access_token",
  }

  EXCLUDED_TOKEN_NAMES = Set{
    "csrf_token", "xsrf_token", "authenticity_token", "anti_csrf_token",
    "captcha_token", "recaptcha_token", "turnstile_token",
  }

  # Substrings that mark a `*_token` param as an opaque, non-JWT token:
  # CSRF/anti-bot tokens, Rails/Devise lifecycle tokens (password reset,
  # email confirmation, account unlock/activation, remember-me, invites),
  # and API pagination cursors. These are random strings, not signed JWTs,
  # so counting them as JWT signals produces false positives on otherwise
  # auth-shaped routes.
  NON_JWT_TOKEN_HINTS = %w[
    csrf xsrf captcha recaptcha turnstile authenticity nonce
    reset unlock confirmation verification invitation activation remember unsubscribe
    page pagination next continuation cursor sync
  ]

  # HTTP auth schemes that are not bearer/JWT; when an Authorization value
  # advertises one of these, the header is not a JWT signal.
  NON_BEARER_SCHEMES = /\A\s*(basic|digest|negotiate|ntlm|hoba|aws4|hmac)\b/i

  AUTH_PATH_PARTS = Set{"auth", "authenticate", "authentication", "login", "signin", "sign_in", "token", "refresh", "jwt"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "jwt"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      signals = endpoint.params.count { |param| jwt_signal?(param) }
      has_bearer_value = endpoint.params.any? { |param| bearer_or_jwt_value?(param.value) }
      is_auth_url = auth_url?(endpoint.url)

      # Require either an unmistakable token value, multiple token/auth
      # signals, or an auth-like route plus a non-CSRF token parameter.
      check = has_bearer_value || signals >= 2 || (is_auth_url && signals >= 1)

      if check
        tag = Tag.new("jwt", "JWT endpoint for token-based authentication, requiring validation of signature, expiration, and claims.", "JWT")
        endpoint.add_tag(tag)
      end
    end
  end

  private def jwt_signal?(param : Param) : Bool
    name = normalize_param_name(param.name)
    return false if EXCLUDED_TOKEN_NAMES.includes?(name)

    if name == "authorization"
      # A populated Authorization header carrying Basic/Digest/etc. is not
      # a JWT; only treat it as a signal when the value is absent or
      # bearer-like.
      return false if non_bearer_authorization?(param.value)
      return true
    end

    return true if STRONG_NAMES.includes?(name)

    # Anything below is a generic `token`/`*_token` name. Drop the
    # well-known opaque tokens before counting it as a JWT signal.
    return false if NON_JWT_TOKEN_HINTS.any? { |hint| name.includes?(hint) }
    return true if name == "token"
    return true if name.ends_with?("_token")

    false
  end

  private def non_bearer_authorization?(value : String) : Bool
    return false if value.empty?
    !!value.match(NON_BEARER_SCHEMES)
  end

  private def bearer_or_jwt_value?(value : String) : Bool
    value_lower = value.downcase
    return true if value_lower.starts_with?("bearer ")

    # Compact JWTs are three base64url-ish segments. Keep this strict
    # enough to avoid tagging arbitrary dotted values.
    !!value.match(/\AeyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*\z/)
  end

  private def auth_url?(url : String) : Bool
    parts = url.downcase.tr("-", "_").split(/[\/\.]+/).reject(&.empty?)
    parts.any? { |part| AUTH_PATH_PARTS.includes?(part) }
  end
end
