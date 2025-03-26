require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderYaml < OutputBuilder
  def print(endpoints : Array(Endpoint))
    message = {"endpoints" => endpoints, "passive_results" => [] of PassiveScanResult}.to_yaml
    ob_puts message
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    message = {"endpoints" => endpoints, "passive_results" => passive_results}.to_yaml
    ob_puts message
  end
end
