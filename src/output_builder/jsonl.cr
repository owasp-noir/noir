require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderJsonl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      ob_puts endpoint.to_json
    end
  end
end
