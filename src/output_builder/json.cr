require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "json", description: "JSON", order: 30, structured: true)]
class OutputBuilderJson < OutputBuilder
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    # `errors` is emitted even when empty. `"errors": []` is the assertion a
    # CI consumer needs — "every analyzer ran" — and an absent key can't make
    # it, since it reads the same as an older Noir that never reported one.
    message = {
      "endpoints"       => endpoints,
      "passive_results" => passive_results,
      "errors"          => analyzer_failures,
    }.to_json
    ob_puts message
  end
end
