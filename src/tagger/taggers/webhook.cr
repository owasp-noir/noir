require "../../models/tagger"
require "../../models/endpoint"

# Flags inbound webhook / callback endpoints — routes that receive
# server-to-server notifications from third parties (payment providers,
# VCS hosts, CI, messaging platforms). They warrant scrutiny for
# signature verification, replay protection, and source-IP trust, and
# the handlers often make outbound requests (SSRF surface).
class WebhookTagger < Tagger
  # Unambiguous webhook path segments — one is enough.
  STRONG_PATH_PARTS = Set{"webhook", "webhooks", "ipn"}

  # Weaker path segments shared with non-webhook routes. Require a POST
  # (or other write) method before flagging on these alone.
  #
  # `notification(s)` are intentionally excluded: an in-app notifications
  # resource (`POST /api/notifications`, `DELETE /notifications/{id}`) is
  # far more common than a notification *webhook*, and it is a write, so
  # the method gate doesn't help. The verb form `notify` is kept — it is
  # the canonical callback term for payment IPNs (`notify_url`).
  MEDIUM_PATH_PARTS = Set{
    "hook", "hooks", "callback", "callbacks", "notify",
  }

  # Webhooks are delivered as non-GET requests. Gate the weaker path
  # signals on "not a read", which — unlike an explicit POST/PUT/PATCH
  # allow-list — also covers wildcard ("ANY"/"*") and blank methods that
  # several analyzers emit for catch-all routes.
  READ_ONLY_METHODS = Set{"GET", "HEAD", "OPTIONS"}

  # OAuth / OIDC / SSO authorization-code callbacks (`/oauth/callback`,
  # `/auth/<provider>/callback`) are browser-redirect handlers, not
  # inbound webhooks — but they share the generic `callback` path word and
  # can arrive as a POST, so they were being mis-tagged. When `callback`
  # is the *only* webhook signal and one of these auth segments is present
  # in the path, suppress it. A genuine payment IPN at `/payments/callback`
  # carries no auth segment and still tags.
  AUTH_CALLBACK_SEGMENTS = Set{
    "oauth", "oauth2", "openid", "oidc", "auth", "authentication",
    "sso", "saml", "login", "signin",
  }
  CALLBACK_PARTS = Set{"callback", "callbacks"}

  # Provider-specific signature/event headers. Any one is a strong
  # webhook indicator on its own.
  SIGNATURE_HEADERS = Set{
    # GitHub / GitLab / Bitbucket / generic
    "x_hub_signature", "x_hub_signature_256", "x_signature",
    "x_webhook_signature", "webhook_signature", "x_hook_signature",
    "x_event_key", "x_github_event", "x_gitlab_event", "x_gitlab_token",
    # Payments
    "stripe_signature", "paypal_transmission_sig",
    "x_razorpay_signature", "x_paystack_signature",
    "x_square_hmacsha256_signature",
    # Chat / comms
    "x_slack_signature", "x_line_signature", "x_zm_signature",
    "x_signature_ed25519", "x_telegram_bot_api_secret_token",
    # E-commerce / SaaS / infra
    "x_shopify_hmac_sha256", "x_shopify_topic",
    "x_wc_webhook_signature", "x_wc_webhook_topic",
    "x_twilio_signature", "x_twilio_email_event_webhook_signature",
    "x_amz_sns_message_type", "x_mandrill_signature",
    "svix_id", "svix_signature", "svix_timestamp",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "webhook"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      header_names = endpoint.params.compact_map do |param|
        normalize_param_name(param.name) if param.param_type == "header"
      end.to_set

      has_signature_header = !(SIGNATURE_HEADERS & header_names).empty?
      is_write = !READ_ONLY_METHODS.includes?(endpoint.method.upcase)

      check = strong_webhook_url?(endpoint.url) ||
              has_signature_header ||
              (is_write && medium_webhook_url?(endpoint.url))

      if check
        tag = Tag.new(
          "webhook",
          "Inbound webhook/callback endpoint; verify signature validation, replay protection, and source-IP trust, and review handlers for SSRF on outbound calls.",
          "Webhook"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  private def strong_webhook_url?(url : String) : Bool
    url_parts(url).any? { |part| STRONG_PATH_PARTS.includes?(part) }
  end

  private def medium_webhook_url?(url : String) : Bool
    parts = url_parts(url)
    matched = parts.select { |part| MEDIUM_PATH_PARTS.includes?(part) }
    return false if matched.empty?

    # A non-callback medium word (hook/hooks/notify) is a webhook signal on
    # its own. Bare callback(s) under an OAuth/SSO segment is an auth
    # redirect handler, not a webhook — drop that lone signal.
    return true if matched.any? { |part| !CALLBACK_PARTS.includes?(part) }
    parts.none? { |part| AUTH_CALLBACK_SEGMENTS.includes?(part) }
  end
end
