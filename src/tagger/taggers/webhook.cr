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
  MEDIUM_PATH_PARTS = Set{
    "hook", "hooks", "callback", "callbacks", "notify", "notification",
    "notifications",
  }

  # Webhooks are delivered as non-GET requests. Gate the weaker path
  # signals on "not a read", which — unlike an explicit POST/PUT/PATCH
  # allow-list — also covers wildcard ("ANY"/"*") and blank methods that
  # several analyzers emit for catch-all routes.
  READ_ONLY_METHODS = Set{"GET", "HEAD", "OPTIONS"}

  # Provider-specific signature/event headers. Any one is a strong
  # webhook indicator on its own.
  SIGNATURE_HEADERS = Set{
    "x_hub_signature", "x_hub_signature_256", "x_signature",
    "x_webhook_signature", "stripe_signature", "x_slack_signature",
    "x_github_event", "x_gitlab_event", "x_gitlab_token",
    "x_event_key", "paypal_transmission_sig",
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
    url_parts(url).any? { |part| MEDIUM_PATH_PARTS.includes?(part) }
  end

  private def url_parts(url : String) : Array(String)
    url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
  end

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
