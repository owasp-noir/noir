require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "json", description: "JSON", order: 30)]
class OutputBuilderJson < OutputBuilder
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    message = {"endpoints" => endpoints, "passive_results" => passive_results}.to_json
    ob_puts message
  end
end
