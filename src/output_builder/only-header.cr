require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyHeader < OutputBuilder
  def print(endpoints : Array(Endpoint))
    headers = [] of String
    cookie = false
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if param.param_type == "header"
          headers << param.name
        elsif param.param_type == "cookie"
          cookie = true
        end
      end
    end

    if cookie
      headers << "Cookie"
    end

    headers.uniq.each do |header|
      puts header.colorize(:light_green).toggle(@is_color)
    end
  end
end
