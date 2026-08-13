require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "yaml", description: "YAML", order: 20, structured: true)]
class OutputBuilderYaml < OutputBuilder
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    message = {"endpoints" => endpoints, "passive_results" => passive_results}.to_yaml
    ob_puts message
  end
end
