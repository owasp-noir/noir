require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyHeader < OutputBuilder
  def print(endpoints : Array(Endpoint))
    headers = [] of String
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if param.param_type == "header"
          headers << param.name
        end
      end
    end

    headers.uniq.each do |header|
      puts header.colorize(:light_green).toggle(@is_color)
    end
  end
end
