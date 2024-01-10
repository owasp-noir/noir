require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyParam < OutputBuilder
  def print(endpoints : Array(Endpoint))
    common_params = [] of String
    targets = ["query", "json", "form"]

    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if targets.includes? param.param_type
          common_params << param.name
        end
      end
    end

    common_params.uniq.each do |common_param|
      puts common_param.colorize(:light_green).toggle(@is_color)
    end
  end
end
