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
# Network errors are warned and recorded (see Deliver#post_export) so a
# misconfigured webhook URL doesn't crash the scan.
class SendWebhook < Deliver
  def run(endpoints : Array(Endpoint), webhook_url : String)
    post_export(Noir::Redact.webhook(webhook_url), "Webhook", "webhook") do
      applied_endpoints = apply_all(endpoints)
      body = {
        "endpoints"      => applied_endpoints,
        "endpoint_count" => applied_endpoints.size,
        "noir_version"   => Noir::VERSION,
      }.to_json
      {webhook_url, body}
    end
  end
end
