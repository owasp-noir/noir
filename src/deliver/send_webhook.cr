require "crest"
require "../models/deliver"

# POSTs the discovered endpoint catalog as a single JSON document to a
# user-supplied webhook URL. The body shape is the same one `-f json`
# would have written:
#
#   {
#     "endpoints":       [<endpoint>...],
#     "endpoint_count":  <int>,
#     "noir_version":    "<semver>"
#   }
#
# Slack incoming webhooks, Discord webhook endpoints, Zapier/n8n
# triggers, and custom internal receivers all accept arbitrary JSON
# bodies, so a single contract covers the common destinations. If a
# receiver needs a more specific format (Slack's `{"text": "..."}`
# blocks, for example), users are expected to route through a
# transformer rather than have noir grow per-platform formatters.
#
# Network errors are swallowed at debug level so a misconfigured
# webhook URL doesn't crash the scan — same posture as the other
# Deliver subclasses.
class SendWebhook < Deliver
  def run(endpoints : Array(Endpoint), webhook_url : String)
    applied_endpoints = apply_all(endpoints)

    body = {
      "endpoints"      => applied_endpoints,
      "endpoint_count" => applied_endpoints.size,
      "noir_version"   => Noir::VERSION,
    }.to_json

    webhook_headers = @headers.dup
    webhook_headers["Content-Type"] = "application/json"
    webhook_headers["Accept"] = "application/json"

    # `form:` is the Crest knob that actually ships the body — see the
    # comment in send_elasticsearch.cr for the rationale.
    Crest::Request.execute(
      method: :post,
      url: webhook_url,
      tls: OpenSSL::SSL::Context::Client.insecure,
      user_agent: "Noir/#{Noir::VERSION}",
      form: body,
      headers: webhook_headers,
      json: true
    )
  rescue e
    @logger.debug "Exception of webhook Delivery"
    @logger.debug_sub e
  end
end
