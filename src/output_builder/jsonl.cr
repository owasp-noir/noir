require "../models/output_builder"
require "../models/endpoint"
require "../models/passive_scan"

@[Noir::OutputFormat(name: "jsonl", description: "JSON Lines", order: 40, structured: true)]
class OutputBuilderJsonl < OutputBuilder
  # Passive findings were dropped from JSONL entirely (only the JSON builder
  # mapped them). Emit each finding on its own line after the endpoints so a
  # `-P` scan's secrets/etc. survive the JSONL pipeline. Consumers tell the
  # two apart by shape (endpoints carry url/method, findings carry id/info).
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    endpoints.each do |endpoint|
      ob_puts endpoint.to_json
    end
    passive_results.each do |result|
      ob_puts result.to_json
    end
  end
end
