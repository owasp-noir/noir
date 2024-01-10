require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyUrl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)
      r_url = baked[:url].colorize(:light_yellow).toggle(@is_color)
      ob_puts "#{r_url}"
    end
  end
end
