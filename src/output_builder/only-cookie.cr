require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyCookie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    cookies = [] of String
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if param.param_type == "cookie"
          cookies << param.name
        end
      end
    end

    cookies.uniq.each do |cookie|
      puts cookie.colorize(:light_green).toggle(@is_color)
    end
  end
end
